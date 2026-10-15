// swift-tools-version: 6.2
import PackageDescription

// Windows build of the upstream MCP library. See UPSTREAM.md for provenance and patches.
let package = Package(
    name: "mcp-swift-sdk",
    products: [.library(name: "MCP", targets: ["MCP"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [.target(name: "MCP", dependencies: [
        .product(name: "SystemPackage", package: "swift-system"),
        .product(name: "Logging", package: "swift-log"),
    ])]
)
