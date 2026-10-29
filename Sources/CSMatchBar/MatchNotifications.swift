import AppKit
import UserNotifications

struct MatchReminder: Equatable {
    let matchID: String
    let title: String
    let body: String
    let url: URL
    /// nil means the source has already reported the match live.
    let date: Date?

    var identifier: String { "followed-match.\(matchID)" }
}

enum ReminderAuthorization {
    case allowed, notDetermined, denied, unavailable
}

@MainActor
protocol MatchNotificationClient: AnyObject {
    func authorization(requestIfNeeded: Bool) async throws -> ReminderAuthorization
    func pendingIdentifiers() async -> Set<String>
    func schedule(_ reminder: MatchReminder) async throws
    func remove(identifiers: [String])
}

@MainActor
final class SystemMatchNotifications: NSObject, MatchNotificationClient, UNUserNotificationCenterDelegate {
    // UNUserNotificationCenter requires an application bundle, so swift run must
    // still allow following matches without attempting to initialize the center.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    func authorization(requestIfNeeded: Bool) async throws -> ReminderAuthorization {
        guard let center else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .notDetermined:
            guard requestIfNeeded else { return .notDetermined }
            return try await center.requestAuthorization(options: [.alert, .sound]) ? .allowed : .denied
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func pendingIdentifiers() async -> Set<String> {
        guard let center else { return [] }
        return Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    func schedule(_ reminder: MatchReminder) async throws {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["matchURL": reminder.url.absoluteString]
        // Use an absolute UTC date so changing the system time zone does not
        // move a reminder away from the match's actual start time.
        let trigger: UNNotificationTrigger?
        if let date = reminder.date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil
        }
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center?.removePendingNotificationRequests(withIdentifiers: identifiers)
        center?.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let rawURL = response.notification.request.content.userInfo["matchURL"] as? String,
           let url = URL(string: rawURL), url.scheme == "https", url.host == "www.hltv.org" {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
