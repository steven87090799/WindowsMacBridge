import Foundation
import BridgeCore

public struct BridgeSettings: Codable, Sendable {
    public var schemaVersion = 1
    public var enabled = false
    public var overrides: [String: ApplicationMode] = [:]
    public var keyboardScope: KeyboardScope = .builtInAndApple834
    public var finderEnabled = false
    public var allowIMEShortcuts = false
    public var inputBackend: InputBackend = .deviceHID
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, overrides, keyboardScope, finderEnabled, allowIMEShortcuts, inputBackend
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        overrides = try values.decode([String: ApplicationMode].self, forKey: .overrides)
        // Existing global-shortcut users retain their scope. New installs request device isolation.
        keyboardScope = try values.decodeIfPresent(KeyboardScope.self, forKey: .keyboardScope) ?? .allKeyboards
        finderEnabled = try values.decodeIfPresent(Bool.self, forKey: .finderEnabled) ?? false
        allowIMEShortcuts = try values.decodeIfPresent(Bool.self, forKey: .allowIMEShortcuts) ?? false
        inputBackend = try values.decodeIfPresent(InputBackend.self, forKey: .inputBackend) ?? .eventTap
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
                settings = BridgeSettings()
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
}
