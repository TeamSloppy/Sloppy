import ProjectDescription

let destinations: Destinations = [
    .iPhone,
    .iPad,
    .mac,
    .appleVision,
    .appleWatch
]

let deploymentTargets: DeploymentTargets = .multiplatform(
    iOS: "17.0",
    macOS: "15.0",
    watchOS: "10.0",
    visionOS: "2.0"
)

let project = Project(
    name: "SloppyClient",
    organizationName: "Sloppy",
    settings: .settings(
        base: [
            "SWIFT_STRICT_CONCURRENCY": "complete"
        ],
        defaultSettings: .recommended
    ),
    targets: [
        // MARK: - Core (no UI dependency)
        .target(
            name: "SloppyClientCore",
            destinations: destinations,
            product: .framework,
            bundleId: "io.sloppy.client.core",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/SloppyClientCore/**"],
            dependencies: [
                .external(name: "Logging")
            ]
        ),

        // MARK: - UI components
        .target(
            name: "SloppyClientUI",
            destinations: destinations,
            product: .framework,
            bundleId: "io.sloppy.client.ui",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/SloppyClientUI/**"],
            dependencies: [
                .external(name: "AdaEngine")
            ]
        ),

        // MARK: - Features
        .target(
            name: "SloppyFeatureOverview",
            destinations: destinations,
            product: .framework,
            bundleId: "io.sloppy.client.feature.overview",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/SloppyFeatureOverview/**"],
            dependencies: [
                .target(name: "SloppyClientCore"),
                .target(name: "SloppyClientUI"),
                .external(name: "AdaEngine")
            ]
        ),
        .target(
            name: "SloppyFeatureProjects",
            destinations: destinations,
            product: .framework,
            bundleId: "io.sloppy.client.feature.projects",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/SloppyFeatureProjects/**"],
            dependencies: [
                .target(name: "SloppyClientCore"),
                .target(name: "SloppyClientUI"),
                .external(name: "AdaEngine")
            ]
        ),
        .target(
            name: "SloppyFeatureAgents",
            destinations: destinations,
            product: .framework,
            bundleId: "io.sloppy.client.feature.agents",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/SloppyFeatureAgents/**"],
            dependencies: [
                .target(name: "SloppyClientCore"),
                .target(name: "SloppyClientUI"),
                .external(name: "AdaEngine")
            ]
        ),

        // MARK: - App
        .target(
            name: "SloppyClient",
            destinations: destinations,
            product: .app,
            bundleId: "io.sloppy.client",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Sloppy",
                "UILaunchScreen": [:]
            ]),
            sources: ["Sources/SloppyClient/**"],
            dependencies: [
                .target(name: "SloppyClientCore"),
                .target(name: "SloppyClientUI"),
                .target(name: "SloppyFeatureOverview"),
                .target(name: "SloppyFeatureProjects"),
                .target(name: "SloppyFeatureAgents"),
                .external(name: "Logging"),
                .external(name: "AdaEngine")
            ]
        ),

        // MARK: - Tests
        .target(
            name: "SloppyClientCoreTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "io.sloppy.client.core.tests",
            deploymentTargets: deploymentTargets,
            sources: ["Tests/SloppyClientCoreTests/**"],
            dependencies: [
                .target(name: "SloppyClientCore")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "SloppyClient",
            shared: true,
            buildAction: .buildAction(targets: ["SloppyClient"]),
            testAction: .targets(["SloppyClientCoreTests"]),
            runAction: .runAction(configuration: .debug, executable: "SloppyClient")
        )
    ]
)
