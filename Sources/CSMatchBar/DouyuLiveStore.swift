import Combine
import Foundation

@MainActor
final class DouyuLiveStore: ObservableObject {
    @Published private(set) var status: DouyuRoomStatus = .checking
    @Published private(set) var lastChecked: Date?

    private let fetchStatus: () async throws -> DouyuRoomStatus
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var lastAttempt: Date?
    private let refreshInterval: TimeInterval = 60

    init(fetchStatus: @escaping () async throws -> DouyuRoomStatus = { try await DouyuRoomClient().fetchStatus() }) {
        self.fetchStatus = fetchStatus
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < refreshInterval { return }
        isRefreshing = true
        lastAttempt = Date()
        defer { isRefreshing = false }

        do {
            status = try await fetchStatus()
            lastChecked = Date()
        } catch {
            // A failed check must not keep showing a previous live/offline state.
            status = .unavailable
            lastChecked = nil
        }
    }
}
