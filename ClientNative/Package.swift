// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SloppyClient",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .executable(name: "SloppyClient", targets: ["SloppyClient"]),
        .library(name: "SloppyClientCore", targets: ["SloppyClientCore"]),
        .library(name: "SloppyClientUI", targets: ["SloppyClientUI"]),
        .library(name: "SloppyFeatureOverview", targets: ["SloppyFeatureOverview"]),
        .library(name: "SloppyFeatureProjects", targets: ["SloppyFeatureProjects"]),
        .library(name: "SloppyFeatureAgents", targets: ["SloppyFeatureAgents"]),
        .library(name: "SloppyFeatureSettings", targets: ["SloppyFeatureSettings"]),
        .library(name: "SloppyFeatureChat", targets: ["SloppyFeatureChat"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "SloppyClientCore",
            dependencies: [
                "CSQLite3",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/SloppyClientCore"
        ),
        .target(
            name: "SloppyClientUI",
            dependencies: [
                "SloppyClientCore"
            ],
            path: "Sources/SloppyClientUI",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SloppyFeatureOverview",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI"
            ],
            path: "Sources/SloppyFeatureOverview"
        ),
        .target(
            name: "SloppyFeatureProjects",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI"
            ],
            path: "Sources/SloppyFeatureProjects"
        ),
        .target(
            name: "SloppyFeatureAgents",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                "SloppyFeatureChat"
            ],
            path: "Sources/SloppyFeatureAgents"
        ),
        .target(
            name: "SloppyFeatureSettings",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI"
            ],
            path: "Sources/SloppyFeatureSettings"
        ),
        .target(
            name: "SloppyFeatureChat",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI"
            ],
            path: "Sources/SloppyFeatureChat"
        ),
        .executableTarget(
            name: "SloppyClient",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                "SloppyFeatureOverview",
                "SloppyFeatureProjects",
                "SloppyFeatureAgents",
                "SloppyFeatureSettings",
                "SloppyFeatureChat",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/SloppyClient"
        ),
        .testTarget(
            name: "SloppyClientCoreTests",
            dependencies: ["SloppyClientCore", "CSQLite3"],
            path: "Tests/SloppyClientCoreTests"
        ),
        .testTarget(
            name: "SloppyFeatureChatTests",
            dependencies: ["SloppyClientCore", "SloppyFeatureChat"],
            path: "Tests/SloppyFeatureChatTests"
        ),
        .systemLibrary(
            name: "CSQLite3",
            path: "Sources/CSQLite3"
        )
    ]
)
