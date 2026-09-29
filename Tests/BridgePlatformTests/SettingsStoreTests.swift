import Foundation
import Testing
import BridgeCore
import BridgePlatform

@MainActor struct SettingsStoreTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "WindowsMacBridge.Tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }

    @Test func freshInstallWorksForChatWhileSensitiveAppsStayProtected() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults).settings
        #expect(settings.enabled)
        #expect(settings.inputBackend == .eventTap)
        #expect(settings.keyboardScope == .allKeyboards)
        #expect(!settings.finderEnabled && settings.allowIMEShortcuts)
        #expect(settings.screenshotAutoCopy)
        #expect(settings.windowsKeyModifier == .option)
        #expect(!settings.winRunEnabled && !settings.winSettingsEnabled && !settings.winTaskViewEnabled)
        #expect(KeyboardLayoutResolver.supports(sourceID: "org.atelierInmu.inputmethod.vChewing.IMECHT", asciiLayoutID: "com.apple.keylayout.ABC", allowIME: settings.allowIMEShortcuts))
        let registry = try ApplicationRegistry()
        #expect(registry.mode(for: "com.openai.codex", overrides: settings.overrides) == .macOS)
        #expect(registry.mode(for: "com.apple.Terminal", overrides: settings.overrides) == .terminal)
        #expect(registry.mode(for: "com.microsoft.VSCode", overrides: settings.overrides) == .ide)
        #expect(registry.mode(for: "com.microsoft.rdc.macos", overrides: settings.overrides) == .remoteWindows)
        #expect(registry.mode(for: "com.utmapp.UTM", overrides: settings.overrides) == .virtualMachine)
    }

    @Test(arguments: [Data("not JSON".utf8), Data(#"{"schemaVersion":999,"enabled":true,"overrides":{}}"#.utf8)])
    func corruptOrFuturePreferencesFailClosedAndRemainUntouched(_ data: Data) {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(data, forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults)
        #expect(!store.settings.enabled)
        #expect(store.settings.overrides.isEmpty)
        #expect(!store.settings.allowIMEShortcuts)
        #expect(!store.settings.screenshotAutoCopy)
        #expect(store.errorMessage != nil)
        #expect(defaults.data(forKey: "bridge.settings.v1") == data)
    }

    @Test func existingIntentionalChoicesSurviveUpdateAndCodexRemovalPersists() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var previous = BridgeSettings()
        previous.enabled = false
        previous.inputBackend = .deviceHID
        previous.keyboardScope = .builtInAndApple834
        previous.overrides = ["com.openai.codex": .ide, "custom.remote": .remoteWindows]
        defaults.set(try JSONEncoder().encode(previous), forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults)
        #expect(store.settings == previous)
        store.update { $0.overrides.removeValue(forKey: "com.openai.codex") }
        #expect(SettingsStore(defaults: defaults).settings.overrides["com.openai.codex"] == nil)
    }

    @Test func recommendedPresetRetainsOtherApplicationRules() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.enabled = false; $0.inputBackend = .deviceHID; $0.finderEnabled = true
            $0.overrides["com.openai.codex"] = .ide
            $0.overrides["custom.browser"] = .remoteWindows
        }
        store.applyRecommendedPreset()
        #expect(store.settings.enabled && store.settings.inputBackend == .eventTap)
        #expect(store.settings.overrides["com.openai.codex"] == .macOS)
        #expect(store.settings.overrides["custom.browser"] == .remoteWindows)
        #expect(!store.settings.finderEnabled)
        #expect(store.settings.screenshotAutoCopy)
        #expect(SettingsStore(defaults: defaults).settings == store.settings)
    }

    @Test func screenshotChoicePersistsAndPresetDoesNotResetIt() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.update { $0.screenshotAutoCopy = false }
        #expect(!SettingsStore(defaults: defaults).settings.screenshotAutoCopy)
        store.applyRecommendedPreset()
        #expect(!store.settings.screenshotAutoCopy)
        store.update { $0.screenshotAutoCopy = true }
        #expect(SettingsStore(defaults: defaults).settings.screenshotAutoCopy)
        store.update { $0.windowsKeyModifier = .command }
        store.update { $0.winRunEnabled = true; $0.winSettingsEnabled = true; $0.winTaskViewEnabled = true }
        store.applyRecommendedPreset()
        #expect(SettingsStore(defaults: defaults).settings.windowsKeyModifier == .command)
        #expect(store.settings.winRunEnabled && store.settings.winSettingsEnabled && store.settings.winTaskViewEnabled)
    }

    @Test func macBookMigrationUsesCommandButExplicitKeyboardChoiceWins() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = Data(#"{"schemaVersion":3,"enabled":true,"overrides":{},"screenshotAutoCopy":true}"#.utf8)
        defaults.set(previous, forKey: "bridge.settings.v1")
        let migrated = SettingsStore(defaults: defaults, portableHost: true)
        #expect(migrated.settings.windowsKeyModifier == .command)
        #expect(migrated.settings.macBookFnControlSwap)
        migrated.update { $0.windowsKeyModifier = .option }
        #expect(SettingsStore(defaults: defaults, portableHost: true).settings.windowsKeyModifier == .option)
    }

    @Test func freshMacBookEnablesFnSwapDefaultAndExplicitOffSurvives() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, portableHost: true)
        #expect(store.settings.macBookFnControlSwap)
        #expect(store.settings.windowsKeyModifier == .command)
        store.update { $0.macBookFnControlSwap = false }
        #expect(!SettingsStore(defaults: defaults, portableHost: true).settings.macBookFnControlSwap)
        store.applyRecommendedPreset()
        #expect(!store.settings.macBookFnControlSwap)
        #expect(!SettingsStore(defaults: defaults, portableHost: true).settings.macBookFnControlSwap)
    }

    @Test func removingBundledCodexRuleRestoresTerminalProtection() throws {
        var settings = BridgeSettings()
        settings.overrides.removeValue(forKey: "com.openai.codex")
        #expect(try ApplicationRegistry().mode(for: "com.openai.codex", overrides: settings.overrides) == .ide)
    }
    @Test func schemaOneMigratesWithoutLosingChoices() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = Data(#"{"schemaVersion":1,"enabled":false,"overrides":{"example.remote":"remoteWindows"},"finderEnabled":true,"allowIMEShortcuts":false,"screenshotAutoCopy":false}"#.utf8)
        defaults.set(legacy, forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults)
        #expect(store.settings.schemaVersion == 3)
        #expect(!store.settings.enabled && store.settings.finderEnabled)
        #expect(store.settings.overrides["example.remote"] == .remoteWindows)
        #expect(!store.settings.screenshotAutoCopy && !store.settings.allowIMEShortcuts)
        #expect(store.settings.windowsKeyModifier == .option)
        #expect(store.settings.textNavigationEnabled && !store.settings.windowSwitcherEnabled)
        store.update { $0.altF4Enabled = true }
        #expect(SettingsStore(defaults: defaults).settings.altF4Enabled)
    }
    @Test func schemaTwoMigratesAndMacBookToggleSurvivesPresetAndRelaunch() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var old = BridgeSettings()
        old.schemaVersion = 2; old.screenshotAutoCopy = false
        old.overrides = ["my.remote": .remoteWindows]
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        object.removeValue(forKey: "macBookFnControlSwap")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults)
        #expect(store.settings.schemaVersion == 3 && !store.settings.macBookFnControlSwap)
        #expect(!store.settings.screenshotAutoCopy && store.settings.overrides == old.overrides)
        store.update { $0.macBookFnControlSwap = true }
        store.applyRecommendedPreset()
        #expect(SettingsStore(defaults: defaults).settings.macBookFnControlSwap)
        #expect(!store.settings.screenshotAutoCopy && store.settings.overrides["my.remote"] == .remoteWindows)
    }
}
