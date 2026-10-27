// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CSMatchBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CSMatchBar", targets: ["CSMatchBar"])
    ],
    targets: [
        .executableTarget(
            name: "CSMatchBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
