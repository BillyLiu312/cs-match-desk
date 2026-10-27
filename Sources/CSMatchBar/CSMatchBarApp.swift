import AppKit
import SwiftUI

@main
struct CSMatchBarApp: App {
    @StateObject private var store: MatchesStore

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
        let store = MatchesStore()
        _store = StateObject(wrappedValue: store)
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
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
        } label: {
            Image(nsImage: Self.menuBarImage)
                .accessibilityLabel("CS Match Desk")
        }
        .menuBarExtraStyle(.window)
    }
}
