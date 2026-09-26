// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowsMacBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .executable(name: "WindowsMacBridge", targets: ["WindowsMacBridge"])
    ],
    targets: [
        .target(name: "BridgeCore"),
        .target(name: "BridgePlatform", dependencies: ["BridgeCore"],
                resources: [.process("Resources")]),
        .executableTarget(name: "WindowsMacBridge", dependencies: ["BridgeCore", "BridgePlatform"]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"]),
        .testTarget(name: "BridgePlatformTests", dependencies: ["BridgeCore", "BridgePlatform"])
    ]
)
