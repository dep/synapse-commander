// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SynapseCommander",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "SynapseCommander",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SynapseCommander"
        ),
        .testTarget(
            name: "SynapseCommanderTests",
            dependencies: ["SynapseCommander"],
            path: "Tests/SynapseCommanderTests"
        )
    ]
)
