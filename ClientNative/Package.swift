// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SloppyClient",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .executable(name: "SloppyClient", targets: ["SloppyClient"]),
        .library(name: "SloppyClientCore", targets: ["SloppyClientCore"]),
        .library(name: "SloppyClientUI", targets: ["SloppyClientUI"]),
        .library(name: "SloppyFeatureOverview", targets: ["SloppyFeatureOverview"]),
        .library(name: "SloppyFeatureProjects", targets: ["SloppyFeatureProjects"]),
        .library(name: "SloppyFeatureAgents", targets: ["SloppyFeatureAgents"]),
        .library(name: "SloppyFeatureSettings", targets: ["SloppyFeatureSettings"]),
        .library(name: "SloppyFeatureChat", targets: ["SloppyFeatureChat"]),
        .library(name: "SloppyLiveActivity", targets: ["SloppyLiveActivity"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(path: "Vendor/Textual"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
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
                "SloppyClientUI",
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/SloppyFeatureChat"
        ),
        .target(
            name: "SloppyLiveActivity",
            dependencies: [
                "SloppyClientCore"
            ],
            path: "Sources/SloppyLiveActivity"
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
                "SloppyLiveActivity",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/SloppyClient",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SloppyClientCoreTests",
            dependencies: ["SloppyClientCore", "SloppyLiveActivity", "CSQLite3"],
            path: "Tests/SloppyClientCoreTests"
        ),
        .testTarget(
            name: "SloppyFeatureChatTests",
            dependencies: ["SloppyClientCore", "SloppyFeatureChat"],
            path: "Tests/SloppyFeatureChatTests"
        ),
        .testTarget(
            name: "SloppyFeatureProjectsTests",
            dependencies: ["SloppyClientCore", "SloppyFeatureProjects"],
            path: "Tests/SloppyFeatureProjectsTests"
        ),
        .systemLibrary(
            name: "CSQLite3",
            path: "Sources/CSQLite3"
        )
    ]
)
