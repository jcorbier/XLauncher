// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XPlaneLauncher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "XPlaneLauncher", targets: ["XPlaneLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "XPlaneLauncher",
            path: "Sources/XPlaneLauncher" // Explicitly pointing here just in case, though standard.
        ),
    ]
)
