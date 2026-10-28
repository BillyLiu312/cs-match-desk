import Foundation

@main
struct DouyuLiveChecks {
    @MainActor
    static func main() async throws {
        try parsesLiveAndOfflineResponses()
        rejectsUnreliableResponses()
        await refreshRecoversAfterFailure()
        await overlappingRefreshesShareOneRequest()
        if CommandLine.arguments.contains("--live-room") {
            let status = try await DouyuRoomClient().fetchStatus()
            print("Douyu room 6657 (\(DouyuRoomClient.roomID)): \(status.title)")
        }
        print("Douyu live status checks passed")
    }

    private static func parsesLiveAndOfflineResponses() throws {
        let live = Data(#"{"error":0,"data":{"room_id":"6979222","room_status":"1"}}"#.utf8)
        let offline = Data(#"{"error":0,"data":{"room_id":6979222,"room_status":2}}"#.utf8)
        let liveStatus = try DouyuRoomClient.parseStatus(live)
        let offlineStatus = try DouyuRoomClient.parseStatus(offline)
        precondition(liveStatus == .live, "Live room was not recognized")
        precondition(offlineStatus == .offline, "Offline room was not recognized")
        precondition(DouyuRoomClient.roomURL.absoluteString == "https://www.douyu.com/6657")
    }

    private static func rejectsUnreliableResponses() {
        let responses = [
            #"{"error":0,"data":{"room_id":"6657","room_status":"1"}}"#,
            #"{"error":0,"data":{"room_id":"6979222","room_status":"0"}}"#,
            #"{"error":0,"data":{"room_id":"6979222","room_status":true}}"#,
            #"{"error":0,"data":{"room_id":"6979222"}}"#,
            #"{"error":0,"data":null}"#,
            #"{"error":101,"data":"房间不存在"}"#,
            "<html>服务暂不可用</html>"
        ]
        for response in responses {
            do {
                _ = try DouyuRoomClient.parseStatus(Data(response.utf8))
                preconditionFailure("Invalid room response produced a live/offline status: \(response)")
            } catch {}
        }
    }

    @MainActor
    private static func refreshRecoversAfterFailure() async {
        var requests = 0
        let store = DouyuLiveStore {
            requests += 1
            if requests == 2 { throw URLError(.notConnectedToInternet) }
            return requests == 1 ? .live : .offline
        }
        precondition(store.status == .checking)
        await store.refresh()
        precondition(store.status == .live && store.lastChecked != nil)
        await store.refresh()
        precondition(requests == 1, "Opening the panel repeatedly should not repeatedly query Douyu")
        await store.refresh(force: true)
        precondition(store.status == .unavailable && store.lastChecked == nil, "Failure left a stale live indicator")
        await store.refresh()
        precondition(requests == 2, "Failed requests should still respect the polling interval")
        await store.refresh(force: true)
        precondition(store.status == .offline && store.lastChecked != nil, "Manual refresh did not recover")
    }

    @MainActor
    private static func overlappingRefreshesShareOneRequest() async {
        var requests = 0
        var completion: CheckedContinuation<DouyuRoomStatus, Error>?
        let store = DouyuLiveStore {
            requests += 1
            return try await withCheckedThrowingContinuation { completion = $0 }
        }
        let first = Task { await store.refresh() }
        while completion == nil { await Task.yield() }
        await store.refresh(force: true)
        precondition(requests == 1, "Overlapping refreshes created duplicate requests")
        completion?.resume(returning: .live)
        await first.value
        precondition(store.status == .live)
    }
}
