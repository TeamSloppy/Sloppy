// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SafariExtension",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SafariExtensionCore", targets: ["SafariExtensionCore"])
    ],
    targets: [
        .target(
            name: "SafariExtensionCore",
            path: "Sources/SafariExtensionCore"
        ),
        .testTarget(
            name: "SafariExtensionCoreTests",
            dependencies: ["SafariExtensionCore"],
            path: "Tests/SafariExtensionCoreTests"
        )
    ]
)
