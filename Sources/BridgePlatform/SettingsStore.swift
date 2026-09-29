import Foundation
import IOKit
import BridgeCore

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var enabled = true
    // This preset is for chat/text use. Remove it to restore Codex's IDE protection.
    public var overrides: [String: ApplicationMode] = ["com.openai.codex": .macOS]
    public var keyboardScope: KeyboardScope = .allKeyboards
    public var finderEnabled = false
    public var allowIMEShortcuts = true
    public var inputBackend: InputBackend = .eventTap
    public var screenshotAutoCopy = true
    public var windowsKeyModifier: WindowsKeyModifier = .option
    public var winRunEnabled = false
    public var winSettingsEnabled = false
    public var winTaskViewEnabled = false
    public var windowSwitcherEnabled = false
    public var windowThumbnailsEnabled = false
    public var finderPermanentDeleteEnabled = false
    public var textNavigationEnabled = true
    public var altF4Enabled = false
    public var altF4QuitLastWindow = false
    public var macBookFnControlSwap = false
    public init() {}
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
        case windowSwitcherEnabled, windowThumbnailsEnabled, finderPermanentDeleteEnabled, textNavigationEnabled, altF4Enabled, altF4QuitLastWindow
        case macBookFnControlSwap, windowsKeyModifier, winRunEnabled, winSettingsEnabled, winTaskViewEnabled
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
        windowSwitcherEnabled = try values.decodeIfPresent(Bool.self, forKey: .windowSwitcherEnabled) ?? false
        windowThumbnailsEnabled = try values.decodeIfPresent(Bool.self, forKey: .windowThumbnailsEnabled) ?? false
        finderPermanentDeleteEnabled = try values.decodeIfPresent(Bool.self, forKey: .finderPermanentDeleteEnabled) ?? false
        textNavigationEnabled = try values.decodeIfPresent(Bool.self, forKey: .textNavigationEnabled) ?? true
        altF4Enabled = try values.decodeIfPresent(Bool.self, forKey: .altF4Enabled) ?? false
        altF4QuitLastWindow = try values.decodeIfPresent(Bool.self, forKey: .altF4QuitLastWindow) ?? false
        macBookFnControlSwap = try values.decodeIfPresent(Bool.self, forKey: .macBookFnControlSwap) ?? false
    }
}

@MainActor public final class SettingsStore {
    private let defaults: UserDefaults
    public private(set) var settings: BridgeSettings
    public private(set) var errorMessage: String?
    private static func portableHost() -> Bool {
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != 0 else { return false }
        defer { IOObjectRelease(battery) }
        return (IORegistryEntryCreateCFProperty(battery, "BatteryInstalled" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.boolValue == true
    }
    public init(defaults: UserDefaults = .standard, portableHost: Bool? = nil) {
        self.defaults = defaults
        let isPortable = portableHost ?? Self.portableHost()
        let defaultModifier: WindowsKeyModifier = isPortable ? .command : .option
        if let data = defaults.data(forKey: "bridge.settings.v1") {
            do {
                let loaded = try JSONDecoder().decode(BridgeSettings.self, from: data)
                guard (1...3).contains(loaded.schemaVersion) else { throw CocoaError(.coderReadCorrupt) }
                settings = loaded
                settings.schemaVersion = 3
                // Older files without these fields get host defaults. A stored
                // false is an explicit choice and must never be overwritten.
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if object["windowsKeyModifier"] == nil { settings.windowsKeyModifier = defaultModifier }
                    if object["macBookFnControlSwap"] == nil { settings.macBookFnControlSwap = isPortable }
                }
            } catch {
                settings = .safeFallback
                errorMessage = "設定無法讀取，已使用停用的安全預設；原資料未覆寫。"
            }
        } else {
            settings = BridgeSettings()
            settings.windowsKeyModifier = defaultModifier
            settings.macBookFnControlSwap = isPortable
        }
    }
    public func update(_ body: (inout BridgeSettings) -> Void) {
        var next = settings
        body(&next)
        do {
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
            $0.windowSwitcherEnabled = preserved.windowSwitcherEnabled
            $0.windowThumbnailsEnabled = preserved.windowThumbnailsEnabled
            $0.finderPermanentDeleteEnabled = preserved.finderPermanentDeleteEnabled
            $0.textNavigationEnabled = preserved.textNavigationEnabled
            $0.altF4Enabled = preserved.altF4Enabled
            $0.altF4QuitLastWindow = preserved.altF4QuitLastWindow
            $0.macBookFnControlSwap = preserved.macBookFnControlSwap
            $0.overrides.merge(existingOverrides) { _, existing in existing }
            $0.overrides["com.openai.codex"] = .macOS
        }
    }
}
