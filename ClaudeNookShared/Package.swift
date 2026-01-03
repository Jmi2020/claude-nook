// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClaudeNookShared",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "ClaudeNookShared",
            targets: ["ClaudeNookShared"]),
    ],
    targets: [
        .target(
            name: "ClaudeNookShared",
            path: "Sources/ClaudeNookShared"
        ),
    ]
)
