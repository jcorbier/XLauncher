// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XLauncherPluginKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "XLauncherPluginKit",
            type: .dynamic,
            targets: ["XLauncherPluginKit"]
        )
    ],
    targets: [
        .target(
            name: "XLauncherPluginKit",
            dependencies: [],
            path: "Sources/XLauncherPluginKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
