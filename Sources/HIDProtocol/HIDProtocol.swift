import Foundation
import BridgeCore

public enum HIDService {
    public static let name = "local.WindowsMacBridge.HIDHelper"
    public static let root = "/Library/Application Support/WindowsMacBridge"
    public static let protocolVersion = 4
}

/// Only bounded policy/status messages cross IPC. Never a stream of typed characters.
@objc public protocol HIDHelperProtocol {
    func configure(_ data: Data, withReply reply: @escaping (Data) -> Void)
    func stop(withReply reply: @escaping () -> Void)
    func requestInputAccess(withReply reply: @escaping (Bool) -> Void)
}
@objc public protocol HIDControllerProtocol {
    func performAction(_ id: String, processID: Int32, generation: UInt64)
}

public struct HIDConfiguration: Codable, Sendable {
    public var version = HIDService.protocolVersion
    public var enabled = false
    public var sessionActive = false
    public var layoutSupported = false
    public var finderEnabled = false
    public var finderBrightnessEnterEnabled = false
    public var screenshotEnabled = false
    public var printScreenBehavior: PrintScreenBehavior = .snipping
    public var keyboardScope: KeyboardScope = .allKeyboards
    public var finderPermanentDeleteEnabled = false
    public var textNavigationEnabled = true
    public var altF4Enabled = false
    public var windowsKeyModifier: WindowsKeyModifier = .option
    public var macBookFnControlSwap = false
    public var winRunEnabled = false
    public var winSettingsEnabled = false
    public var winTaskViewEnabled = false
    public var diagnostics = false
    public var processID: Int32 = 0
    public var bundleID = ""
    public var mode: ApplicationMode = .disabled
    public var isBrowser = false
    public var generation: UInt64 = 0
    // Action epoch can change without invalidating another keyboard's physical holds.
    public var actionGeneration: UInt64 = 0
    public var restartToken: UInt64 = 0
    public var deviceInputs: [DeviceInputPreference] = []
    public init() {}
    public var valid: Bool {
        version == HIDService.protocolVersion && bundleID.utf8.count <= 256 && processID >= 0 &&
            deviceInputs.count <= 16 && deviceInputs.allSatisfy { !$0.identity.isEmpty && $0.identity.utf8.count <= 128 } &&
            Set(deviceInputs.map(\.identity)).count == deviceInputs.count &&
            (!enabled || (processID > 0 && !bundleID.isEmpty))
    }
    public var context: ApplicationContext {
        .init(processID: processID, bundleID: bundleID, mode: mode, isBrowser: isBrowser)
    }
}
public struct HIDStatus: Codable, Equatable, Sendable {
    public var version = HIDService.protocolVersion
    public var state = "未連線"
    public var driverReady = false
    public var permissions = false
    public var secureInput = false
    public var capturedDevices = 0
    public var eligibleDevices = 0
    public var manualPassThrough = false
    public var emergencyPaused = false
    public var processed: UInt64 = 0
    public var translated: UInt64 = 0
    public var maxMicroseconds: Double = 0
    public var lastRule: String?
    public var devices: [HIDDeviceStatus] = []
    public init() {}
}
public struct HIDDeviceStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: String { identity }
    public var identity: String
    public var product: String
    public var builtIn: Bool
    public var captured: Bool
    public init(identity: String, product: String, builtIn: Bool, captured: Bool) {
        self.identity = identity; self.product = product; self.builtIn = builtIn; self.captured = captured
    }
}

public enum HIDActionCodec {
    public static func encode(_ action: ShortcutAction) -> String {
        switch action {
        case .finder(let value): "finder." + value.rawValue
        case .system(let value): "system." + value.rawValue
        case .window(.close): "window.close"
        case .screenshot(let kind): "screenshot." + kind.rawValue
        }
    }
    public static func decode(_ id: String) -> ShortcutAction? {
        if id.hasPrefix("finder."), let value = FinderAction(rawValue: String(id.dropFirst(7))) { return .finder(value) }
        if id.hasPrefix("system."), let value = SystemAction(rawValue: String(id.dropFirst(7))) { return .system(value) }
        if id == "window.close" { return .window(.close) }
        if id.hasPrefix("screenshot."), let kind = ScreenshotKind(rawValue: String(id.dropFirst(11))) { return .screenshot(kind) }
        return nil
    }
}
