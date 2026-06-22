// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SloppySafari",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SloppySafariCore", targets: ["SloppySafariCore"])
    ],
    targets: [
        .target(
            name: "SloppySafariCore",
            path: "Sources/SloppySafariCore"
        ),
        .testTarget(
            name: "SloppySafariCoreTests",
            dependencies: ["SloppySafariCore"],
            path: "Tests/SloppySafariCoreTests"
        )
    ]
)
