// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Anchor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Anchor", targets: ["AnchorApp"]),
        .library(name: "AnchorCore", targets: ["AnchorCore"])
    ],
    dependencies: [
        // SQLite local persistence.
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        // Dynamic Island / notch overlay window.
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", from: "1.1.0"),
        // Auto-update.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        // MARK: - Core (no UI dependency, fully testable)
        .target(
            name: "AnchorCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/AnchorCore"
        ),

        // MARK: - Daemon (Socket server + browser bridge)
        .target(
            name: "AnchorDaemon",
            dependencies: ["AnchorCore"],
            path: "Sources/AnchorDaemon"
        ),

        // MARK: - Hooks (reserved for future AI agent integration, v3+)
        .target(
            name: "AnchorHooks",
            dependencies: ["AnchorCore"],
            path: "Sources/AnchorHooks"
        ),

        // MARK: - App (SwiftUI + AppKit shell)
        .executableTarget(
            name: "AnchorApp",
            dependencies: [
                "AnchorCore",
                "AnchorDaemon",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AnchorApp"
        ),

        // MARK: - Tests
        .testTarget(
            name: "AnchorCoreTests",
            dependencies: ["AnchorCore"],
            path: "Tests/AnchorCoreTests"
        ),
        .testTarget(
            name: "AnchorDaemonTests",
            dependencies: ["AnchorDaemon"],
            path: "Tests/AnchorDaemonTests"
        )
    ]
)
