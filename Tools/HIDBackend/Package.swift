// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BridgeHIDBackend",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BridgeHIDHelper", targets: ["BridgeHIDHelper"])],
    dependencies: [.package(name: "WindowsMacBridge", path: "../..")],
    targets: [
        .target(name: "VirtualHID", publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-std=c++23"]),
                              .headerSearchPath("../../SDKOverride"),
                              .headerSearchPath("../../SDK/include"),
                              .headerSearchPath("../../SDK/vendor/vendor/include")],
                linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]),
        .target(name: "HIDLifecycle"),
        .executableTarget(name: "BridgeHIDHelper", dependencies: ["VirtualHID", "HIDLifecycle",
            .product(name: "BridgeCore", package: "WindowsMacBridge"),
            .product(name: "HIDProtocol", package: "WindowsMacBridge")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "VirtualHIDTests", dependencies: ["VirtualHID", "HIDLifecycle"])
    ]
)
