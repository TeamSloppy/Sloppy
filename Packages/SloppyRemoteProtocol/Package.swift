// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SloppyRemoteProtocol",
    platforms: [.macOS(.v15), .iOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "SloppyRemoteProtocol", targets: ["SloppyRemoteProtocol"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "SloppyRemoteProtocol",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")]
        ),
    ]
)
