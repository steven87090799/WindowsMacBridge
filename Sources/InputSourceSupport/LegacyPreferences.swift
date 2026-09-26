import Foundation

/// Import only known non-content preferences, never activation state, history or login items.
enum LegacyPreferences {
    static let domain = "com.local.VChewingGuard"
    static func validated(_ source: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        if let n = source["debounceMilliseconds"] as? Int {
            result[AppSettings.debounceKey] = min(1_200, max(200, n))
        }
        if let n = source["startupDelayMilliseconds"] as? Int {
            result[AppSettings.startupDelayKey] = min(5_000, max(0, n))
        }
        if let raw = source["hotkeyPreset"] as? String, let preset = HotkeyPreset(rawValue: raw) {
            result[AppSettings.hotkeyKey] = preset.rawValue
        }
        return result
    }
}
