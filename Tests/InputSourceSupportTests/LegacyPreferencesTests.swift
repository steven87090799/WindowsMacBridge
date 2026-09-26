import Testing
@testable import InputSourceSupport

struct LegacyPreferencesTests {
    @Test func importOnlyWhitelistedPreferences() {
        let imported = LegacyPreferences.validated([
            "debounceMilliseconds": 650, "startupDelayMilliseconds": 2000,
            "hotkeyPreset": "controlCommandSpace", "guardEnabled": true,
            "diagnostics.vChewingRestoreCount": 99, "unexpectedContent": "must-not-import"
        ])
        #expect(imported.count == 3)
        #expect(imported[AppSettings.debounceKey] as? Int == 650)
        #expect(imported[AppSettings.startupDelayKey] as? Int == 2000)
        #expect(imported[AppSettings.hotkeyKey] as? String == "controlCommandSpace")
        #expect(imported[AppSettings.guardEnabledKey] == nil)
    }
    @Test func invalidTypesAndUnknownPresetsAreIgnored() {
        #expect(LegacyPreferences.validated([
            "debounceMilliseconds": "slow", "startupDelayMilliseconds": [1, 2],
            "hotkeyPreset": "unregistered-key", "guardEnabled": true
        ]).isEmpty)
    }
    @Test func importedDelaysAreClamped() {
        let imported = LegacyPreferences.validated(["debounceMilliseconds": -1, "startupDelayMilliseconds": 99_999])
        #expect(imported[AppSettings.debounceKey] as? Int == 200)
        #expect(imported[AppSettings.startupDelayKey] as? Int == 5000)
    }
    @Test func absentLegacySettingsRemainAbsent() {
        #expect(LegacyPreferences.validated([:]).isEmpty)
    }
}
