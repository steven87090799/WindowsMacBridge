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
        .target(name: "BridgeWorkGate"),
        .target(name: "BridgeCore", dependencies: ["BridgeWorkGate"]),
        .target(name: "HIDProtocol", dependencies: ["BridgeCore"]),
        .target(name: "VirtualHID", path: "Tools/HIDBackend/Sources/VirtualHID", publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-std=c++23"]), .headerSearchPath("../../SDKOverride"),
                              .headerSearchPath("../../SDK/include"), .headerSearchPath("../../SDK/vendor/vendor/include")],
                linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]),
        .target(name: "HIDLifecycle", path: "Tools/HIDBackend/Sources/HIDLifecycle"),
        .target(name: "HIDRuntime", dependencies: ["VirtualHID", "HIDLifecycle", "BridgeCore", "HIDProtocol"],
                path: "Tools/HIDBackend/Sources/HIDRuntime", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "InputSourceCore"),
        // The imported Carbon/TIS adapter is main-queue confined; keep its Swift 5
        // language mode while the host, policy and keyboard engine remain Swift 6.
        .target(name: "InputSourceSupport", dependencies: ["InputSourceCore", "BridgeCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "BridgePlatform", dependencies: ["BridgeCore", "HIDProtocol"],
                resources: [.process("Resources")]),
        .executableTarget(name: "WindowsMacBridge", dependencies: ["BridgeCore", "BridgePlatform", "InputSourceCore", "InputSourceSupport", "HIDRuntime"]),
        // Offline codec measurement only; explicitly excluded from App packaging.
        .executableTarget(name: "BridgeImageBenchmark", dependencies: ["BridgeCore", "BridgePlatform"], path: "Tools/ImageBenchmark"),
        .testTarget(name: "VirtualHIDTests", dependencies: ["VirtualHID", "HIDLifecycle"], path: "Tools/HIDBackend/Tests/VirtualHIDTests"),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "InputSourceSupportTests", dependencies: ["InputSourceSupport"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "InputSourceCoreTests", dependencies: ["InputSourceCore", "BridgeCore"]),
        .testTarget(name: "BridgePlatformTests", dependencies: ["BridgeCore", "BridgePlatform", "HIDProtocol"])
    ]
)
