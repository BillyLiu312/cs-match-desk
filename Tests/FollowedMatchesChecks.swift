import Foundation

@main
struct FollowedMatchesChecks {
    @MainActor
    static func main() async {
        await followsPersistAndUnfollowingCancels()
        await refreshReschedulesWithoutDuplicates()
        await liveTransitionOnlyNotifiesOnce()
        await elapsedRemindersAreNotReplayedAfterRestart()
        await completedAndAlreadyStartedMatchesDoNotNotify()
        await deniedPermissionKeepsFollowAndCanRecover()
        await unavailableNotificationsKeepFollow()
        await schedulingFailureCanRecover()
        await oneFailureDoesNotBlockOtherMatches()
        await restartRemovesOnlyOrphanedMatchReminders()
        await unfollowWhileSchedulingRemovesLateRequest()
        await matchChangesWhileSchedulingUseLatestSchedule()
        print("Followed match and notification checks passed")
    }

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private static func followsPersistAndUnfollowingCancels() async {
        let defaults = MemoryDefaults()
        let client = NotificationStub()
        let match = makeMatch()
        let store = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start })
        store.toggle(match)
        precondition(store.isFollowing(match), "Follow state should update immediately")
        await store.waitForSynchronization()
        precondition(client.requests.count == 1 && client.requests[0].date == match.startsAt)
        precondition(client.requests[0].url == match.url, "Notification must link to its match")
        precondition(client.permissionRequests == 1, "First follow must request notification permission")

        let restored = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start })
        precondition(restored.isFollowing(match), "Follow state did not survive restart")
        restored.toggle(match)
        precondition(!restored.isFollowing(match))
        await restored.waitForSynchronization()
        precondition(client.pending.isEmpty, "Unfollowing left a pending notification")
        let restarted = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start })
        precondition(!restarted.isFollowing(match), "Unfollowing did not persist")
    }

    @MainActor
    private static func refreshReschedulesWithoutDuplicates() async {
        let client = NotificationStub()
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        store.update(matches: [makeMatch()])
        await store.waitForSynchronization()
        precondition(client.requests.count == 1, "Unchanged refresh duplicated the reminder")
        let delayed = makeMatch(offset: 7_200)
        store.update(matches: [delayed])
        await store.waitForSynchronization()
        precondition(client.requests.count == 2 && client.pending.count == 1)
        precondition(client.pending.values.first?.date == delayed.startsAt, "Changed start time was not applied")
        store.update(matches: [])
        await store.waitForSynchronization()
        precondition(store.isFollowing(delayed) && client.pending.count == 1, "Missing scrape data lost a follow")
    }

    @MainActor
    private static func liveTransitionOnlyNotifiesOnce() async {
        let client = NotificationStub()
        let defaults = MemoryDefaults()
        let store = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start })
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        let live = makeMatch(status: .live)
        store.update(matches: [live])
        await store.waitForSynchronization()
        precondition(client.requests.count == 2 && client.requests.last?.date == nil, "Early live transition must notify immediately")
        store.update(matches: [live])
        await store.waitForSynchronization()
        let restored = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start })
        restored.synchronize()
        await restored.waitForSynchronization()
        precondition(client.requests.count == 2, "Live notification repeated on refresh or restart")
    }

    @MainActor
    private static func elapsedRemindersAreNotReplayedAfterRestart() async {
        let client = NotificationStub()
        let defaults = MemoryDefaults()
        let store = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start })
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        client.pending.removeAll() // System has delivered the timer.
        let restored = FollowedMatchesStore(defaults: defaults, notifications: client, now: { start.addingTimeInterval(4_000) })
        restored.update(matches: [makeMatch(status: .live)])
        await restored.waitForSynchronization()
        precondition(client.requests.count == 1, "Delivered reminder replayed after restart")
    }

    @MainActor
    private static func completedAndAlreadyStartedMatchesDoNotNotify() async {
        let client = NotificationStub()
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch(id: "completed", status: .completed))
        store.toggle(makeMatch(id: "live", status: .live))
        store.toggle(makeMatch(id: "past", offset: -3_600))
        await store.waitForSynchronization()
        precondition(client.requests.isEmpty, "Following a past or already-live match sent a stale reminder")
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        store.update(matches: [makeMatch(status: .completed)])
        await store.waitForSynchronization()
        precondition(client.pending.isEmpty, "Completed match kept its future timer")
    }

    @MainActor
    private static func deniedPermissionKeepsFollowAndCanRecover() async {
        let client = NotificationStub()
        client.access = .denied
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        precondition(store.isFollowing(makeMatch()) && store.notificationMessage != nil)
        precondition(client.requests.isEmpty)
        client.access = .allowed
        store.synchronize()
        await store.waitForSynchronization()
        precondition(client.pending.count == 1 && store.notificationMessage == nil, "Enabling notification permission did not recover")
    }

    @MainActor
    private static func unavailableNotificationsKeepFollow() async {
        let client = NotificationStub()
        client.access = .unavailable
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        precondition(store.isFollowing(makeMatch()) && store.notificationMessage != nil)
        precondition(client.requests.isEmpty)
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        precondition(store.notificationMessage == nil, "No follows should leave no notification warning")
    }

    @MainActor
    private static func schedulingFailureCanRecover() async {
        let client = NotificationStub()
        client.shouldFail = true
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch())
        await store.waitForSynchronization()
        precondition(store.notificationMessage != nil && store.isFollowing(makeMatch()))
        client.shouldFail = false
        store.synchronize()
        await store.waitForSynchronization()
        precondition(client.pending.count == 1 && store.notificationMessage == nil)
    }

    @MainActor
    private static func oneFailureDoesNotBlockOtherMatches() async {
        let client = NotificationStub()
        client.failedMatchIDs = ["a"]
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch(id: "a"))
        store.toggle(makeMatch(id: "b"))
        await store.waitForSynchronization()
        precondition(client.pending["followed-match.b"] != nil, "One failed reminder blocked another match")
        precondition(store.notificationMessage != nil)
    }

    @MainActor
    private static func restartRemovesOnlyOrphanedMatchReminders() async {
        let client = NotificationStub()
        let unrelated = MatchReminder(matchID: "other", title: "Other", body: "", url: makeMatch().url, date: start)
        client.pending = ["followed-match.removed": unrelated, "other-feature": unrelated]
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.synchronize()
        await store.waitForSynchronization()
        precondition(client.pending["followed-match.removed"] == nil, "Orphaned reminder remained after restart")
        precondition(client.pending["other-feature"] != nil, "Synchronization removed an unrelated notification")
        precondition(client.permissionRequests == 0, "Starting with no follows should not request permission")
    }

    @MainActor
    private static func unfollowWhileSchedulingRemovesLateRequest() async {
        let client = NotificationStub()
        client.pauseNextSchedule = true
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch())
        while client.scheduling == nil { await Task.yield() }
        store.toggle(makeMatch())
        client.resumeSchedule()
        await store.waitForSynchronization()
        precondition(client.pending.isEmpty && !store.isFollowing(makeMatch()), "In-flight schedule recreated a canceled reminder")
    }

    @MainActor
    private static func matchChangesWhileSchedulingUseLatestSchedule() async {
        let client = NotificationStub()
        client.pauseNextSchedule = true
        let store = FollowedMatchesStore(defaults: MemoryDefaults(), notifications: client, now: { start })
        store.toggle(makeMatch())
        while client.scheduling == nil { await Task.yield() }
        let delayed = makeMatch(offset: 7_200)
        store.update(matches: [delayed])
        client.resumeSchedule()
        await store.waitForSynchronization()
        precondition(client.pending.count == 1 && client.pending.values.first?.date == delayed.startsAt)
    }

    private static func makeMatch(id: String = "123", offset: TimeInterval = 3_600, status: Match.Status = .upcoming) -> Match {
        Match(
            id: id, team1: "Alpha", team2: "Bravo", team1LogoURL: nil, team2LogoURL: nil,
            event: "Test Cup", stage: nil, bestOf: "bo3", startsAt: start.addingTimeInterval(offset),
            status: status, stars: 3, score1: nil, score2: nil, mapWins1: nil, mapWins2: nil,
            url: URL(string: "https://www.hltv.org/matches/\(id)")!
        )
    }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

@MainActor
private final class NotificationStub: MatchNotificationClient {
    var access: ReminderAuthorization = .allowed
    var permissionRequests = 0
    var requests: [MatchReminder] = []
    var pending: [String: MatchReminder] = [:]
    var shouldFail = false
    var failedMatchIDs: Set<String> = []
    var pauseNextSchedule = false
    var scheduling: CheckedContinuation<Void, Never>?

    func authorization(requestIfNeeded: Bool) async throws -> ReminderAuthorization {
        if requestIfNeeded { permissionRequests += 1 }
        return access
    }

    func pendingIdentifiers() async -> Set<String> { Set(pending.keys) }

    func schedule(_ reminder: MatchReminder) async throws {
        if pauseNextSchedule {
            pauseNextSchedule = false
            await withCheckedContinuation { scheduling = $0 }
        }
        if shouldFail || failedMatchIDs.contains(reminder.matchID) { throw URLError(.unknown) }
        requests.append(reminder)
        pending[reminder.identifier] = reminder
    }

    func resumeSchedule() {
        scheduling?.resume()
        scheduling = nil
    }

    func remove(identifiers: [String]) {
        for id in identifiers { pending.removeValue(forKey: id) }
    }
}
