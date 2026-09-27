// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowsMacBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .library(name: "HIDProtocol", targets: ["HIDProtocol"]),
        .executable(name: "WindowsMacBridge", targets: ["WindowsMacBridge"])
    ],
    targets: [
        .target(name: "BridgeCore"),
        .target(name: "HIDProtocol", dependencies: ["BridgeCore"]),
        .target(name: "InputSourceCore"),
        // The imported Carbon/TIS adapter is main-queue confined; keep its Swift 5
        // language mode while the host, policy and keyboard engine remain Swift 6.
        .target(name: "InputSourceSupport", dependencies: ["InputSourceCore", "BridgeCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "BridgePlatform", dependencies: ["BridgeCore", "HIDProtocol"],
                resources: [.process("Resources")]),
        .executableTarget(name: "WindowsMacBridge", dependencies: ["BridgeCore", "BridgePlatform", "InputSourceCore", "InputSourceSupport"]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "InputSourceCoreTests", dependencies: ["InputSourceCore", "BridgeCore"]),
        .testTarget(name: "InputSourceSupportTests", dependencies: ["InputSourceSupport", "InputSourceCore", "BridgeCore"]),
        .testTarget(name: "BridgePlatformTests", dependencies: ["BridgeCore", "BridgePlatform", "HIDProtocol"])
    ]
)
