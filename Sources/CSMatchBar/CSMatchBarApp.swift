import AppKit
import SwiftUI

@main
struct CSMatchBarApp: App {
    @StateObject private var store: MatchesStore
    @StateObject private var douyuLive: DouyuLiveStore
    @StateObject private var followedMatches: FollowedMatchesStore

    private static let menuBarImage: NSImage = {
        if
            let url = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 28, height: 12)
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(systemSymbolName: "scope", accessibilityDescription: "CS Match Desk")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }()

    init() {
        let followedMatches = FollowedMatchesStore()
        let store = MatchesStore(followedMatches: followedMatches)
        let douyuLive = DouyuLiveStore()
        _store = StateObject(wrappedValue: store)
        _followedMatches = StateObject(wrappedValue: followedMatches)
        _douyuLive = StateObject(wrappedValue: douyuLive)
        Task { @MainActor in
            if ProcessInfo.processInfo.environment["CSMATCH_EXPORT_VRS"] == "1" {
                do {
                    let count = try await HLTVScraper().exportValveTopTeamLogos()
                    print("Exported \(count) VRS team logos")
                } catch {
                    print("VRS logo export failed: \(error.localizedDescription)")
                }
                NSApplication.shared.terminate(nil)
            } else {
                store.start()
                douyuLive.start()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
                .environmentObject(douyuLive)
                .environmentObject(followedMatches)
        } label: {
            Image(nsImage: Self.menuBarImage)
                .accessibilityLabel("CS Match Desk")
        }
        .menuBarExtraStyle(.window)
    }
}
