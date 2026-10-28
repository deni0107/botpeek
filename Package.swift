// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BotPeek",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BotPeek", targets: ["BotPeek"]),
        .library(name: "BotPeekCore", targets: ["BotPeekCore"]),
    ],
    targets: [
        // Platform-independent logic: roster parsing, attention detection, queues,
        // reply routing, animation plans. Builds and tests on Linux as well as macOS.
        .target(
            name: "BotPeekCore",
            path: "Sources/BotPeekCore"
        ),
        // The native macOS app (AppKit + SwiftUI). Every file is guarded by
        // `#if canImport(AppKit)` so `swift test` also runs on Linux.
        .executableTarget(
            name: "BotPeek",
            dependencies: ["BotPeekCore"],
            path: "Sources/BotPeek"
        ),
        .testTarget(
            name: "BotPeekCoreTests",
            dependencies: ["BotPeekCore"],
            path: "Tests/BotPeekCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
