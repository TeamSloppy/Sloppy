// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SloppyA2UI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SloppyA2UI", targets: ["SloppyA2UI"])],
    targets: [
        .target(name: "SloppyA2UI"),
        .testTarget(name: "SloppyA2UITests", dependencies: ["SloppyA2UI"], resources: [.copy("Fixtures")]),
    ]
)
