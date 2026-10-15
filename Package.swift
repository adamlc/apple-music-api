// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "itunes-api",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "itunes-api",
            dependencies: [.product(name: "Hummingbird", package: "hummingbird")],
            // Embed an Info.plist so macOS can show the "control Music" permission prompt
            // for this binary instead of attributing it to whatever launched it.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Resources/Info.plist"]),
            ]
        ),
    ]
)
