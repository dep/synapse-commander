// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyCommander",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MyCommander",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MyCommander"
        ),
        .testTarget(
            name: "MyCommanderTests",
            dependencies: ["MyCommander"],
            path: "Tests/MyCommanderTests"
        )
    ]
)
