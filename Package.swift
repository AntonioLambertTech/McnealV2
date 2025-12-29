// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "McNealProtocol",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "McNealProtocol",
            targets: ["McNealProtocol"]),
    ],
    dependencies: [
        // No external dependencies - uses Swift CryptoKit
    ],
    targets: [
        .target(
            name: "McNealProtocol",
            dependencies: []),
        .testTarget(
            name: "McNealProtocolTests",
            dependencies: ["McNealProtocol"]),
    ]
)
