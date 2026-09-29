import Foundation
import BridgeCore

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var enabled = true
    // This preset is for chat/text use. Remove it to restore Codex's IDE protection.
    public var overrides: [String: ApplicationMode] = ["com.openai.codex": .macOS]
    public var keyboardScope: KeyboardScope = .allKeyboards
    public var finderEnabled = false
    public var allowIMEShortcuts = true
    public var inputBackend: InputBackend = .eventTap
    public var screenshotAutoCopy = true
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
    }
}

@MainActor public final class SettingsStore {
    private let defaults: UserDefaults
    public private(set) var settings: BridgeSettings
    public private(set) var errorMessage: String?
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "bridge.settings.v1") {
            do {
                let loaded = try JSONDecoder().decode(BridgeSettings.self, from: data)
                guard loaded.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                settings = loaded
            } catch {
                settings = .safeFallback
                errorMessage = "設定無法讀取，已使用停用的安全預設；原資料未覆寫。"
            }
        } else { settings = BridgeSettings() }
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
            let screenshotAutoCopy = $0.screenshotAutoCopy
            $0 = BridgeSettings()
            $0.screenshotAutoCopy = screenshotAutoCopy
            $0.overrides.merge(existingOverrides) { _, existing in existing }
            $0.overrides["com.openai.codex"] = .macOS
        }
    }
}
