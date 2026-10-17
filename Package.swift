// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "nMapMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "nMapMac", targets: ["NMapMac"]),
    ],
    targets: [
        .target(
            name: "NMapMacCore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "NMapMac",
            dependencies: ["NMapMacCore"]
        ),
        .testTarget(
            name: "NMapMacTests",
            dependencies: ["NMapMacCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
