import Combine
import Foundation

@MainActor
final class FollowedMatchesStore: ObservableObject {
    private struct Follow: Codable {
        var match: Match
        var reminderHandled: Bool
        var scheduledDate: Date?
    }

    @Published private(set) var followedIDs: Set<String> = []
    @Published private(set) var notificationMessage: String?

    private var follows: [String: Follow] = [:]
    private let defaults: UserDefaults
    private let notifications: MatchNotificationClient
    private let now: () -> Date
    private let storageKey = "followedMatches.v1"
    private var needsSync = false
    private var shouldRequestPermission = false
    private var syncTask: Task<Void, Never>?
    private var installed: [String: MatchReminder] = [:]

    init(
        defaults: UserDefaults = .standard,
        notifications: MatchNotificationClient? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.notifications = notifications ?? SystemMatchNotifications()
        self.now = now
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: Follow].self, from: data) {
            follows = saved
            followedIDs = Set(saved.keys)
        }
    }

    func isFollowing(_ match: Match) -> Bool { followedIDs.contains(match.id) }

    func toggle(_ match: Match) {
        if follows.removeValue(forKey: match.id) != nil {
            notifications.remove(identifiers: ["followed-match.\(match.id)"])
            installed.removeValue(forKey: match.id)
        } else {
            follows[match.id] = Follow(match: match, reminderHandled: match.status != .upcoming)
            shouldRequestPermission = true
        }
        persist()
        synchronize()
    }

    func update(matches: [Match]) {
        for match in matches {
            if follows[match.id] != nil { follows[match.id]?.match = match }
        }
        // Missing matches may simply be outside the currently fetched window.
        // Keep their saved start time and follow state until explicitly unfollowed.
        persist()
        synchronize()
    }

    func synchronize() {
        needsSync = true
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            while self.needsSync {
                self.needsSync = false
                await self.syncReminders()
            }
            self.syncTask = nil
        }
    }

    /// Also lets deterministic tests wait for all queued follow/refresh changes.
    func waitForSynchronization() async {
        await syncTask?.value
    }

    private func syncReminders() async {
        let requestPermission = shouldRequestPermission
        shouldRequestPermission = false
        do {
            let authorization = try await notifications.authorization(requestIfNeeded: requestPermission)
            switch authorization {
            case .allowed: notificationMessage = nil
            case .denied: notificationMessage = "已保存关注；开赛提醒需在系统设置 → 通知中允许 CS Match Desk 通知。"
            case .notDetermined: notificationMessage = "已保存关注；允许通知后才能收到开赛提醒。"
            case .unavailable: notificationMessage = "已保存关注；请通过打包的 CS Match Desk.app 使用系统提醒。"
            }
            if follows.isEmpty { notificationMessage = nil }

            let pending = await notifications.pendingIdentifiers()
            let ownedPending = pending.filter { $0.hasPrefix("followed-match.") }
            let followedRequests = Set(follows.keys.map { "followed-match.\($0)" })
            notifications.remove(identifiers: Array(ownedPending.subtracting(followedRequests)))
            guard authorization == .allowed else { return }

            for id in follows.keys.sorted() {
                guard var follow = follows[id] else { continue }
                let match = follow.match
                let identifier = "followed-match.\(id)"
                let currentDate = now()
                // An accepted timer that has reached its deadline must not be
                // sent again on refresh, relaunch, or a later live transition.
                if let scheduledDate = follow.scheduledDate, scheduledDate <= currentDate {
                    follow.reminderHandled = true
                }
                if match.status == .completed { follow.reminderHandled = true }
                if follow.reminderHandled {
                    if match.status == .completed { notifications.remove(identifiers: [identifier]) }
                    follows[id] = follow
                    continue
                }

                let reminderDate: Date?
                if match.status == .live {
                    reminderDate = nil
                } else if match.startsAt > currentDate {
                    reminderDate = match.startsAt
                } else {
                    // Do not send a backlog of stale reminders after relaunch.
                    follow.reminderHandled = true
                    follows[id] = follow
                    continue
                }
                let reminder = MatchReminder(
                    matchID: id,
                    title: "\(match.team1) vs \(match.team2)",
                    body: match.status == .live ? "\(match.event) · 比赛已开始" : "\(match.event) · 已到计划开赛时间",
                    url: match.url,
                    date: reminderDate
                )
                if installed[id] == reminder && pending.contains(identifier) { continue }
                do {
                    try await notifications.schedule(reminder)
                } catch {
                    // One failed request must not prevent other followed
                    // matches from receiving their reminders.
                    notificationMessage = follows.isEmpty ? nil : "关注已保存，但部分开赛提醒设置失败；请刷新重试。"
                    continue
                }
                // A user can unfollow or a refresh can update the match while
                // notification scheduling is suspended. The next pass reconciles it.
                guard var latest = follows[id] else {
                    notifications.remove(identifiers: [identifier])
                    continue
                }
                latest.scheduledDate = reminderDate
                latest.reminderHandled = reminderDate == nil
                follows[id] = latest
                installed[id] = reminder
                persist()
            }
            persist()
        } catch {
            notificationMessage = follows.isEmpty ? nil : "关注已保存，但开赛提醒设置失败；请刷新重试。"
        }
    }

    private func persist() {
        followedIDs = Set(follows.keys)
        if let data = try? JSONEncoder().encode(follows) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
