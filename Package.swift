// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchSpotify",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Vendor/DynamicNotchKit")
    ],
    targets: [
        .executableTarget(
            name: "NotchSpotify",
            dependencies: ["DynamicNotchKit"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
