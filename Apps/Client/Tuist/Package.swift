// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "Logging": .framework,
        "AdaEngine": .framework
    ]
)
#endif

let package = Package(
    name: "SloppyClient",
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(name: "AdaEngine", path: "../../../Vendor/AdaEngine")
    ]
)
