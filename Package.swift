// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WheelOfTools",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WheelCore"),
        .executableTarget(name: "WheelOfTools", dependencies: ["WheelCore"]),
        .executableTarget(name: "wot-cli", dependencies: ["WheelCore"]),
    ]
)
