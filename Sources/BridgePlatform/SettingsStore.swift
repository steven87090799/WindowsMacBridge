import Foundation
import BridgeCore

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 5
    public var enabled = true
    // This preset is for chat/text use. Remove it to restore Codex's IDE protection.
    public var overrides: [String: ApplicationMode] = ["com.openai.codex": .macOS]
    public var keyboardScope: KeyboardScope = .allKeyboards
    public var finderEnabled = false
    public var allowIMEShortcuts = true
    public var inputBackend: InputBackend = .deviceHID
    public var screenshotAutoCopy = true
    public var windowsKeyModifier: WindowsKeyModifier = .command
    public var winRunEnabled = false
    public var winSettingsEnabled = false
    public var winTaskViewEnabled = false
    public var finderPermanentDeleteEnabled = false
    public var textNavigationEnabled = true
    public var altF4Enabled = false
    public var macBookFnControlSwap = false
    public var finderBrightnessEnterEnabled = false
    public var remoteSources: [RemoteSourcePreference] = []
    public var deviceInputs: [DeviceInputPreference] = []
    public var printScreenBehavior: PrintScreenBehavior = .snipping
    public init() {}
    /// Remote preference changes must not advance physical HID generation or release its keys.
    public var physicalPolicySettings: Self {
        var value = self; value.remoteSources = []; value.deviceInputs = []; return value
    }
    public var valid: Bool {
        remoteSources.count <= 32 && deviceInputs.count <= 16 &&
        remoteSources.allSatisfy { !$0.identity.isEmpty && $0.identity.utf8.count <= 256 } &&
        deviceInputs.allSatisfy { !$0.identity.isEmpty && $0.identity.utf8.count <= 128 } &&
        Set(remoteSources.map(\.identity)).count == remoteSources.count && Set(deviceInputs.map(\.identity)).count == deviceInputs.count
    }
    public static var safeFallback: Self {
        var settings = Self()
        settings.enabled = false
        settings.overrides = [:]
        settings.allowIMEShortcuts = false
        settings.screenshotAutoCopy = false
        return settings
    }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, overrides, keyboardScope, finderEnabled, allowIMEShortcuts, inputBackend, screenshotAutoCopy
        case finderPermanentDeleteEnabled, textNavigationEnabled, altF4Enabled
        case macBookFnControlSwap, windowsKeyModifier, winRunEnabled, winSettingsEnabled, winTaskViewEnabled
        case finderBrightnessEnterEnabled, remoteSources, deviceInputs, printScreenBehavior
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        overrides = try values.decode([String: ApplicationMode].self, forKey: .overrides)
        // Stored preferences, including explicit pass-through overrides, always win.
        keyboardScope = try values.decodeIfPresent(KeyboardScope.self, forKey: .keyboardScope) ?? .allKeyboards
        finderEnabled = try values.decodeIfPresent(Bool.self, forKey: .finderEnabled) ?? false
        allowIMEShortcuts = try values.decodeIfPresent(Bool.self, forKey: .allowIMEShortcuts) ?? false
        inputBackend = try values.decodeIfPresent(InputBackend.self, forKey: .inputBackend) ?? .eventTap
        screenshotAutoCopy = try values.decodeIfPresent(Bool.self, forKey: .screenshotAutoCopy) ?? true
        windowsKeyModifier = try values.decodeIfPresent(WindowsKeyModifier.self, forKey: .windowsKeyModifier) ?? .option
        winRunEnabled = try values.decodeIfPresent(Bool.self, forKey: .winRunEnabled) ?? false
        winSettingsEnabled = try values.decodeIfPresent(Bool.self, forKey: .winSettingsEnabled) ?? false
        winTaskViewEnabled = try values.decodeIfPresent(Bool.self, forKey: .winTaskViewEnabled) ?? false
        finderPermanentDeleteEnabled = try values.decodeIfPresent(Bool.self, forKey: .finderPermanentDeleteEnabled) ?? false
        textNavigationEnabled = try values.decodeIfPresent(Bool.self, forKey: .textNavigationEnabled) ?? true
        altF4Enabled = try values.decodeIfPresent(Bool.self, forKey: .altF4Enabled) ?? false
        macBookFnControlSwap = try values.decodeIfPresent(Bool.self, forKey: .macBookFnControlSwap) ?? false
        finderBrightnessEnterEnabled = try values.decodeIfPresent(Bool.self, forKey: .finderBrightnessEnterEnabled) ?? false
        // The old global role cannot safely be assigned to every source. Ignore it; explicit
        // legacy backend/App choices remain intact. The next save removes the obsolete field.
        remoteSources = try values.decodeIfPresent([RemoteSourcePreference].self, forKey: .remoteSources) ?? []
        deviceInputs = try values.decodeIfPresent([DeviceInputPreference].self, forKey: .deviceInputs) ?? []
        printScreenBehavior = try values.decodeIfPresent(PrintScreenBehavior.self, forKey: .printScreenBehavior) ?? .snipping
    }
}

@MainActor public final class SettingsStore {
    private let defaults: UserDefaults
    public private(set) var settings: BridgeSettings
    public private(set) var errorMessage: String?
    public init(defaults: UserDefaults = .standard, portableHost: Bool? = nil) {
        self.defaults = defaults
        let defaultModifier: WindowsKeyModifier = .command
        if let data = defaults.data(forKey: "bridge.settings.v1") {
            do {
                guard data.count <= 64 * 1024 else { throw CocoaError(.coderReadCorrupt) }
                let loaded = try JSONDecoder().decode(BridgeSettings.self, from: data)
                guard (1...5).contains(loaded.schemaVersion), loaded.valid else { throw CocoaError(.coderReadCorrupt) }
                settings = loaded
                settings.schemaVersion = 5
                // Older files without these fields get host defaults. A stored
                // false is an explicit choice and must never be overwritten.
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if object["windowsKeyModifier"] == nil { settings.windowsKeyModifier = defaultModifier }
                    if object["macBookFnControlSwap"] == nil { settings.macBookFnControlSwap = false }
                }
            } catch {
                settings = .safeFallback
                errorMessage = "設定無法讀取，已使用停用的安全預設；原資料未覆寫。"
            }
        } else {
            settings = BridgeSettings()
            settings.windowsKeyModifier = defaultModifier
            settings.macBookFnControlSwap = false
        }
    }
    public func update(_ body: (inout BridgeSettings) -> Void) {
        var next = settings
        body(&next)
        do {
            guard next.valid else { throw CocoaError(.coderInvalidValue) }
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: "bridge.settings.v1")
            settings = next; errorMessage = nil
        } catch { errorMessage = "設定儲存失敗。" }
    }
    /// Preserve app-specific choices; reapply only the shortcut preset and Codex chat rule.
    public func applyRecommendedPreset() {
        update {
            let existingOverrides = $0.overrides
            let preserved = $0
            $0 = BridgeSettings()
            $0.screenshotAutoCopy = preserved.screenshotAutoCopy
            $0.windowsKeyModifier = preserved.windowsKeyModifier
            $0.winRunEnabled = preserved.winRunEnabled
            $0.winSettingsEnabled = preserved.winSettingsEnabled
            $0.winTaskViewEnabled = preserved.winTaskViewEnabled
            $0.finderPermanentDeleteEnabled = preserved.finderPermanentDeleteEnabled
            $0.textNavigationEnabled = preserved.textNavigationEnabled
            $0.altF4Enabled = preserved.altF4Enabled
            $0.macBookFnControlSwap = preserved.macBookFnControlSwap
            $0.finderBrightnessEnterEnabled = preserved.finderBrightnessEnterEnabled
            $0.remoteSources = preserved.remoteSources
            $0.deviceInputs = preserved.deviceInputs
            $0.printScreenBehavior = preserved.printScreenBehavior
            $0.overrides.merge(existingOverrides) { _, existing in existing }
            $0.overrides["com.openai.codex"] = .macOS
        }
    }
    /// One explicit setup preset; preserve per-App/remote/device choices and
    /// user key placement. Setup never opens system settings or grants TCC.
    public func prepareOneClickSetup(hasBuiltInAppleKeyboard: Bool) {
        update {
            $0.enabled = true; $0.inputBackend = .deviceHID; $0.keyboardScope = .allKeyboards
            $0.screenshotAutoCopy = true; $0.allowIMEShortcuts = true
            $0.finderEnabled = true; $0.textNavigationEnabled = true; $0.altF4Enabled = true
            $0.winRunEnabled = true; $0.winSettingsEnabled = true; $0.winTaskViewEnabled = true
            $0.finderBrightnessEnterEnabled = false
            if hasBuiltInAppleKeyboard { $0.macBookFnControlSwap = true }
            $0.overrides["com.openai.codex"] = .macOS
        }
    }
}
