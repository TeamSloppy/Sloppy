// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchPetAdaPrototype",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "NotchPetAdaPrototype", targets: ["NotchPetAdaPrototype"]),
    ],
    dependencies: [
        .package(path: "../../../Vendor/AdaEngine"),
    ],
    targets: [
        .executableTarget(
            name: "NotchPetAdaPrototype",
            dependencies: [
                .product(name: "AdaEngine", package: "AdaEngine"),
            ],
            path: "Sources/NotchPetAdaPrototype"
        ),
    ]
)
