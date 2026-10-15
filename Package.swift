// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "apple-music-api",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "apple-music-api",
            dependencies: [.product(name: "Hummingbird", package: "hummingbird")]
        ),
        .testTarget(
            name: "apple-music-apiTests",
            dependencies: ["apple-music-api"]
        ),
    ]
)
