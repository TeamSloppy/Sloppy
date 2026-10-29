// swift-tools-version: 6.2
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let siblingEngine = packageDirectory.appendingPathComponent("../../../AdaEngine").standardizedFileURL
let adaEnginePath: String
if let override = environment["ADAENGINE_PATH"], !override.isEmpty {
    adaEnginePath = override
} else if environment["ADAENGINE_LOCAL"] != "0",
          FileManager.default.fileExists(atPath: siblingEngine.appendingPathComponent("Package.swift").path) {
    adaEnginePath = siblingEngine.path
} else {
    adaEnginePath = "../../Vendor/AdaEngine"
}

let package = Package(
    name: "SloppyClient",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .executable(name: "SloppyClient", targets: ["SloppyClient"]),
        .library(name: "SloppyTerminalHost", targets: ["CSloppyTerminal"]),
        .library(name: "SloppyClientCore", targets: ["SloppyClientCore"]),
        .library(name: "SloppyClientUI", targets: ["SloppyClientUI"]),
        .library(name: "SloppyFeatureOverview", targets: ["SloppyFeatureOverview"]),
        .library(name: "SloppyFeatureProjects", targets: ["SloppyFeatureProjects"]),
        .library(name: "SloppyFeatureAgents", targets: ["SloppyFeatureAgents"]),
        .library(name: "SloppyFeatureSettings", targets: ["SloppyFeatureSettings"]),
        .library(name: "SloppyFeatureChat", targets: ["SloppyFeatureChat"])
    ],
    dependencies: [
        .package(name: "SloppyComputerControl", path: "../../Packages/SloppyComputerControl"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(name: "AdaEngine", path: adaEnginePath),
        .package(name: "AdaMCP", path: "../../Vendor/AdaMCP"),
        environment["SLOPPY_SWIFTTERM_PATH"].map { .package(name: "SwiftTerm", path: $0) }
            ?? .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "caa1bdd3f1396c5b0ed66121f299d1c8b42bc94c")
    ],
    targets: [
        .target(name: "CSloppyTerminal", linkerSettings: [.linkedLibrary("util", .when(platforms: [.linux]))]),
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
            path: "Sources/SloppyClientUI",
            resources: [
                .process("Resources")
            ],
            plugins: [
                .plugin(name: "TextureAtlasBuildPlugin", package: "AdaEngine")
            ]
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
                "SloppyFeatureChat",
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyFeatureAgents"
        ),
        .target(
            name: "SloppyFeatureSettings",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyFeatureSettings"
        ),
        .target(
            name: "SloppyFeatureChat",
            dependencies: [
                "SloppyClientCore",
                "SloppyClientUI",
                .product(name: "AdaEngine", package: "AdaEngine")
            ],
            path: "Sources/SloppyFeatureChat"
        ),
        .executableTarget(
            name: "SloppyClient",
            dependencies: [
                "CSloppyTerminal",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                "SloppyClientCore",
                "SloppyClientUI",
                "SloppyFeatureOverview",
                "SloppyFeatureProjects",
                "SloppyFeatureAgents",
                "SloppyFeatureSettings",
                "SloppyFeatureChat",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AdaEngine", package: "AdaEngine"),
                .product(name: "AdaMCPPlugin", package: "AdaMCP", condition: .when(platforms: [.macOS, .iOS, .visionOS])),
            ],
            path: "Sources/SloppyClient"
        ),
        .testTarget(
            name: "SloppyClientWorkspaceTests",
            dependencies: ["SloppyClient", "SloppyClientCore"],
            path: "Tests/SloppyClientWorkspaceTests"
        ),
        .testTarget(
            name: "SloppyClientCoreTests",
            dependencies: ["SloppyClientCore"],
            path: "Tests/SloppyClientCoreTests"
        ),
        .testTarget(
            name: "SloppyFeatureChatTests",
            dependencies: ["SloppyClientCore", "SloppyFeatureChat"],
            path: "Tests/SloppyFeatureChatTests"
        )
    ]
)
