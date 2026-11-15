// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MindowCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MindowCore", targets: ["MindowCore"])],
    targets: [
        .target(name: "MindowCore"),
        .testTarget(name: "MindowCoreTests", dependencies: ["MindowCore"]),
    ]
)
