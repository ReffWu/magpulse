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
    targets: [
        .executableTarget(
            name: "MagPulse",
            path: "Sources/MagPulse"
        )
    ]
)
