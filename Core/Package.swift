// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "ProxyCatCore", targets: ["ProxyCatCore"]),
        .executable(name: "DemoServer", targets: ["DemoServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.23.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "ProxyCatCore",
                dependencies: [
                    .product(name: "NIOCore", package: "swift-nio"),
                    .product(name: "NIOPosix", package: "swift-nio"),
                    .product(name: "NIOHTTP1", package: "swift-nio"),
                    .product(name: "NIOWebSocket", package: "swift-nio"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "NIOSSL", package: "swift-nio-ssl"),
                ]),
        .executableTarget(
            name: "DemoServer",
            dependencies: [
                "ProxyCatCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOWebSocket", package: "swift-nio-ssl"),
            ]),
        .testTarget(
            name: "DemoServerTests",
            dependencies: ["DemoServer"]),
    ]
)
