// swift-tools-version: 6.0
import PackageDescription

// Vendored from https://github.com/MrKai77/DynamicNotchKit at 1.1.0 (cd0b3e5), MIT — see LICENSE.
// Local change: `DynamicNotch.accessory`, a tab drawn hanging below the expanded notch,
// sliding out from under it once the notch has finished opening.
// Upstream masks everything to a single NotchShape, so there was no way to draw outside it.
let package = Package(
    name: "DynamicNotchKit",
    platforms: [.macOS(.v14)], // .v14 for withAnimation's completion, used by the accessory,
    products: [
        .library(name: "DynamicNotchKit", targets: ["DynamicNotchKit"])
    ],
    targets: [
        .target(name: "DynamicNotchKit", path: "Sources")
    ]
)
