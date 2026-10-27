import AppKit
import Combine
import Foundation

@MainActor
final class TeamLogoCache: ObservableObject {
    static let shared = TeamLogoCache()

    @Published private(set) var generation = 0

    private var memory: [String: NSImage] = [:]
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directory = base
            .appendingPathComponent("dev.csmatchinfo.menubar", isDirectory: true)
            .appendingPathComponent("TeamLogosV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for teamName: String, darkMode: Bool) -> NSImage? {
        let key = normalized(teamName)
        let memoryKey = "\(darkMode ? "dark" : "light"):\(key)"
        if let image = memory[memoryKey] { return image }
        let diskURL = fileURL(for: key)
        let bundledBaseURL = Bundle.main.resourceURL?
            .appendingPathComponent("TeamLogos", isDirectory: true)
            .appendingPathComponent(key)
        let darkURL = Bundle.main.resourceURL?
            .appendingPathComponent("TeamLogosDark", isDirectory: true)
            .appendingPathComponent(key)
            .appendingPathExtension("png")
        let bundledPNG = bundledBaseURL?.appendingPathExtension("png")
        let bundledSVG = bundledBaseURL?.appendingPathExtension("svg")
        guard let image = (darkMode ? darkURL.flatMap(NSImage.init(contentsOf:)) : nil)
            ?? bundledPNG.flatMap(NSImage.init(contentsOf:))
            ?? bundledSVG.flatMap(NSImage.init(contentsOf:))
            ?? NSImage(contentsOf: diskURL)
        else {
            return nil
        }
        memory[memoryKey] = image
        return image
    }

    func store(_ image: NSImage, for teamName: String) {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else { return }

        let key = normalized(teamName)
        do {
            try data.write(to: fileURL(for: key), options: .atomic)
            memory["light:\(key)"] = image
            generation &+= 1
        } catch {
            // A failed logo cache write should never block match updates.
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("png")
    }

    private func normalized(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics
        let scalars = folded.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(scalars).replacingOccurrences(of: "__", with: "_")
    }
}
