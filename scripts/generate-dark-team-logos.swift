import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate-dark-team-logos SOURCE_DIR OUTPUT_DIR\n", stderr)
    exit(2)
}

let fileManager = FileManager.default
let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sourceFiles = try fileManager.contentsOfDirectory(
    at: sourceDirectory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
).filter { ["png", "svg"].contains($0.pathExtension.lowercased()) }

let canvasSize = 160
var generated: [String] = []

for sourceURL in sourceFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    guard let source = NSImage(contentsOf: sourceURL) else { continue }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize,
        pixelsHigh: canvasSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }

    bitmap.size = NSSize(width: canvasSize, height: canvasSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
    source.draw(
        in: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let pixels = bitmap.bitmapData else { continue }
    var visiblePixels = 0
    var darkNeutralPixels = 0
    var colorfulPixels = 0
    for y in 0..<canvasSize {
        for x in 0..<canvasSize {
            let offset = y * bitmap.bytesPerRow + x * 4
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.08 else { continue }
            visiblePixels += 1

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let saturation = maximum - minimum
            if luminance < 0.34 && saturation < 0.18 {
                darkNeutralPixels += 1
            }
            if saturation >= 0.25 {
                colorfulPixels += 1
            }
        }
    }

    guard visiblePixels > 0 else { continue }
    let darkRatio = Double(darkNeutralPixels) / Double(visiblePixels)
    let colorfulRatio = Double(colorfulPixels) / Double(visiblePixels)
    guard darkRatio >= 0.55, colorfulRatio <= 0.25 else { continue }

    for y in 0..<canvasSize {
        for x in 0..<canvasSize {
            let offset = y * bitmap.bytesPerRow + x * 4
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else { continue }

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let saturation = maximum - minimum
            if saturation < 0.18 {
                let inverted = 1 - luminance
                let component = UInt8((inverted * 255).rounded())
                pixels[offset] = component
                pixels[offset + 1] = component
                pixels[offset + 2] = component
            }
        }
    }

    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    let name = sourceURL.deletingPathExtension().lastPathComponent
    try data.write(to: outputDirectory.appendingPathComponent(name).appendingPathExtension("png"), options: .atomic)
    generated.append(name)
}

print("Generated \(generated.count) dark team logos: \(generated.joined(separator: ", "))")
