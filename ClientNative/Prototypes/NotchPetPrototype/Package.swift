// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchPetPrototype",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "NotchPetPrototype", targets: ["NotchPetPrototype"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchPetPrototype",
            path: "Sources/NotchPetPrototype"
        ),
    ]
)
