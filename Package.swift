// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MagPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MagPulse", targets: ["MagPulse"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MagPulse",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MagPulse",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
