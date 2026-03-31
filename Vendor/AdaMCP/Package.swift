// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AdaMCP",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "AdaMCPCore", targets: ["AdaMCPCore"]),
        .library(name: "AdaMCPServer", targets: ["AdaMCPServer"]),
        .library(name: "AdaMCPPlugin", targets: ["AdaMCPPlugin"])
    ],
    dependencies: [
        .package(path: "../AdaEngine"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.74.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
    ],
    targets: [
        .target(
            name: "AdaMCPCore",
            dependencies: [
                .product(name: "AdaEngine", package: "AdaEngine"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "AdaMCPServer",
            dependencies: [
                "AdaMCPCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ]
        ),
        .target(
            name: "AdaMCPPlugin",
            dependencies: [
                "AdaMCPCore",
                "AdaMCPServer",
                .product(name: "AdaEngine", package: "AdaEngine"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "AdaMCPTests",
            dependencies: [
                "AdaMCPCore",
                "AdaMCPServer",
                "AdaMCPPlugin",
                .product(name: "AdaEngine", package: "AdaEngine"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SystemPackage", package: "swift-system")
            ],
            path: "Tests/AdaMCPTests"
        )
    ]
)
