// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SloppyClient",
    platforms: [
        .macOS(.v15),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "SloppyClient", targets: ["SloppyClient"]),
        .library(name: "SloppyClientCore", targets: ["SloppyClientCore"]),
        .library(name: "SloppyClientUI", targets: ["SloppyClientUI"]),
        .library(name: "SloppyFeatureOverview", targets: ["SloppyFeatureOverview"]),
        .library(name: "SloppyFeatureProjects", targets: ["SloppyFeatureProjects"]),
        .library(name: "SloppyFeatureAgents", targets: ["SloppyFeatureAgents"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(name: "AdaEngine", path: "../../Vendor/AdaEngine")
    ],
    targets: [
        .target(
            name: "SloppyClientCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/SloppyClientCore"
        ),
        .target(
            name: "SloppyClientUI",
            dependencies: [
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyClientUI"
        ),
        .target(
            name: "SloppyFeatureOverview",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyFeatureOverview"
        ),
        .target(
            name: "SloppyFeatureProjects",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyFeatureProjects"
        ),
        .target(
            name: "SloppyFeatureAgents",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyFeatureAgents"
        ),
        .executableTarget(
            name: "SloppyClient",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                "SloppyFeatureOverview",
                "SloppyFeatureProjects",
                "SloppyFeatureAgents",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyClient"
        ),
        .testTarget(
            name: "SloppyClientCoreTests",
            dependencies: ["SloppyClientCore"],
            path: "Tests/SloppyClientCoreTests"
        )
    ]
)
