import Foundation
import Testing
import BridgeCore
import BridgePlatform

@MainActor struct SettingsStoreTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "WindowsMacBridge.Tests." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }

    @Test func unsupportedSchemaUpdateCannotReplaceReadablePreferences() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.update { $0.finderEnabled = false }
        let previous = store.settings, data = defaults.data(forKey: "bridge.settings.v1")
        store.update { $0.schemaVersion = 999 }
        #expect(store.errorMessage != nil && store.settings == previous)
        #expect(defaults.data(forKey: "bridge.settings.v1") == data)
        #expect(SettingsStore(defaults: defaults).settings == previous)
    }

    @Test func rulePreviewUsesSavedOptionsWithoutEnablingOrChangingSettings() {
        var settings = BridgeSettings()
        settings.enabled = false; settings.windowsKeyModifier = .option; settings.winRunEnabled = true
        settings.finderEnabled = false; settings.screenshotAutoCopy = false
        let original = settings
        let context = ApplicationContext(processID: 10, bundleID: "com.apple.TextEdit", mode: .macOS)
        let preview = settings.shortcutPreview(context: context)
        let run = ShortcutPreview.evaluate(.init(keyCode: 15, modifiers: .option), configuration: preview)
        #expect(run.decision == .rewrite(keyCode: 49, modifiers: .command, ruleID: "windows.winR"))
        #expect(ShortcutPreview.evaluate(.init(keyCode: 1, modifiers: [.option,.shift]), configuration: preview).decision == .passThrough)
        let disabled = settings.shortcutPreview(context: context, enabled: false)
        #expect(ShortcutPreview.evaluate(.init(keyCode: 8, modifiers: .control), configuration: disabled).decision == .passThrough)
        #expect(settings == original && !settings.enabled)
    }

    @Test func oversizedUpdatePreservesTheLastReadableSettings() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.update { $0.macBookFnControlSwap = true }
        let previous = store.settings
        let saved = try #require(defaults.data(forKey: "bridge.settings.v1"))
        store.update {
            $0.overrides = Dictionary(uniqueKeysWithValues: (0..<2000).map {
                ("com.example.application.\($0).long-bundle-identifier", ApplicationMode.macOS)
            })
        }
        #expect(store.errorMessage != nil)
        #expect(store.settings == previous)
        #expect(defaults.data(forKey: "bridge.settings.v1") == saved)
        #expect(SettingsStore(defaults: defaults).settings == previous)
        store.update { $0.finderEnabled = false }
        #expect(store.errorMessage == nil)
        #expect(!SettingsStore(defaults: defaults).settings.finderEnabled)
    }

    @Test func encodedSizeBoundaryRoundTripsAndOneExtraByteIsRejected() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var boundary = store.settings
        boundary.overrides = ["a": .macOS]
        let baseSize = try JSONEncoder().encode(boundary).count
        let key = String(repeating: "a", count: 1 + SettingsStore.maximumEncodedBytes - baseSize)
        boundary.overrides = [key: .macOS]
        #expect(try JSONEncoder().encode(boundary).count == SettingsStore.maximumEncodedBytes)
        store.update { $0 = boundary }
        #expect(store.errorMessage == nil)
        #expect(SettingsStore(defaults: defaults).settings == boundary)
        let saved = defaults.data(forKey: "bridge.settings.v1")
        store.update { $0.overrides = [key + "a": .macOS] }
        #expect(store.errorMessage != nil)
        #expect(store.settings == boundary)
        #expect(defaults.data(forKey: "bridge.settings.v1") == saved)
    }

    @Test func freshInstallWorksForChatWhileSensitiveAppsStayProtected() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults).settings
        #expect(settings.enabled)
        #expect(settings.inputBackend == .eventTap)
        #expect(settings.keyboardScope == .allKeyboards)
        #expect(settings.finderEnabled && settings.allowIMEShortcuts)
        #expect(settings.screenshotAutoCopy)
        #expect(settings.windowsKeyModifier == .option)
        #expect(!settings.winRunEnabled && !settings.winSettingsEnabled && !settings.winTaskViewEnabled)
        #expect(KeyboardLayoutResolver.supports(sourceID: "org.atelierInmu.inputmethod.vChewing.IMECHT", asciiLayoutID: "com.apple.keylayout.ABC", allowIME: settings.allowIMEShortcuts))
        let registry = try ApplicationRegistry()
        #expect(registry.mode(for: "com.openai.codex", overrides: settings.overrides) == .macOS)
        #expect(registry.mode(for: "com.apple.Terminal", overrides: settings.overrides) == .terminal)
        #expect(registry.mode(for: "com.microsoft.VSCode", overrides: settings.overrides) == .ide)
        #expect(registry.mode(for: "com.microsoft.rdc.macos", overrides: settings.overrides) == .remoteWindows)
        #expect(registry.mode(for: "com.edovia.Screens", overrides: settings.overrides) == .remoteWindows)
        #expect(ApplicationMode.remoteWindows.title == "Remote Session — Pass-through")
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
        #expect(store.settings.finderEnabled)
        #expect(store.settings.screenshotAutoCopy)
        #expect(SettingsStore(defaults: defaults).settings == store.settings)
    }

    @Test(arguments: [true, false]) func oneClickSetupEnablesFeaturesAndPreservesPerAppChoices(_ builtIn: Bool) {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.enabled = false; $0.inputBackend = .eventTap; $0.screenshotAutoCopy = false
            $0.windowsKeyModifier = .option; $0.overrides["custom.remote"] = .remoteWindows
        }
        store.prepareOneClickSetup(hasBuiltInAppleKeyboard: builtIn)
        #expect(store.settings.enabled && store.settings.inputBackend == .eventTap)
        #expect(store.settings.screenshotAutoCopy && store.settings.finderEnabled)
        #expect(store.settings.winRunEnabled && store.settings.winSettingsEnabled && store.settings.winTaskViewEnabled)
        #expect(!store.settings.finderBrightnessEnterEnabled && !store.settings.macBookFnControlSwap)
        #expect(store.settings.windowsKeyModifier == .option && store.settings.overrides["custom.remote"] == .remoteWindows)
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
        store.update { $0.windowsKeyModifier = .option }
        store.update { $0.winRunEnabled = true; $0.winSettingsEnabled = true; $0.winTaskViewEnabled = true }
        store.applyRecommendedPreset()
        #expect(SettingsStore(defaults: defaults).settings.windowsKeyModifier == .option)
        #expect(store.settings.winRunEnabled && store.settings.winSettingsEnabled && store.settings.winTaskViewEnabled)
    }

    @Test func legacyCommandWinPreferenceMigratesWithoutLosingOtherSettings() throws {
        for portable in [false, true] {
            let (name, defaults) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let legacy = Data(#"{"schemaVersion":6,"enabled":true,"overrides":{"custom.remote":"remoteWindows"},"windowsKeyModifier":"command","screenshotAutoCopy":false,"macBookFnControlSwap":true,"winRunEnabled":true,"altF4Enabled":false}"#.utf8)
            defaults.set(legacy, forKey: "bridge.settings.v1")
            let store = SettingsStore(defaults: defaults, portableHost: portable)
            #expect(store.errorMessage == nil && store.settings.enabled)
            #expect(store.settings.windowsKeyModifier == .option)
            #expect(store.settings.macBookFnControlSwap && store.settings.winRunEnabled)
            #expect(!store.settings.screenshotAutoCopy && !store.settings.altF4Enabled)
            #expect(store.settings.overrides["custom.remote"] == .remoteWindows)
            store.applyRecommendedPreset()
            let data = try #require(defaults.data(forKey: "bridge.settings.v1"))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["windowsKeyModifier"] as? String == "option")
            let relaunched = SettingsStore(defaults: defaults, portableHost: portable)
            #expect(relaunched.settings == store.settings)
        }
    }
    @Test func macBookMigrationUsesOptionAndPreservesFnChoice() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = Data(#"{"schemaVersion":3,"enabled":true,"overrides":{},"screenshotAutoCopy":true}"#.utf8)
        defaults.set(previous, forKey: "bridge.settings.v1")
        let migrated = SettingsStore(defaults: defaults, portableHost: true)
        #expect(migrated.settings.windowsKeyModifier == .option)
        #expect(!migrated.settings.macBookFnControlSwap)
        migrated.update { $0.windowsKeyModifier = .option }
        #expect(SettingsStore(defaults: defaults, portableHost: true).settings.windowsKeyModifier == .option)
    }

    @Test func freshMacBookPreservesFnByDefaultAndExplicitOffSurvives() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, portableHost: true)
        #expect(!store.settings.macBookFnControlSwap)
        #expect(store.settings.windowsKeyModifier == .option)
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
        #expect(store.settings.schemaVersion == 6)
        #expect(!store.settings.enabled && store.settings.finderEnabled)
        #expect(store.settings.overrides["example.remote"] == .remoteWindows)
        #expect(!store.settings.screenshotAutoCopy && !store.settings.allowIMEShortcuts)
        #expect(store.settings.windowsKeyModifier == .option)
        #expect(store.settings.textNavigationEnabled)
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
        #expect(store.settings.schemaVersion == 6 && !store.settings.macBookFnControlSwap)
        #expect(!store.settings.screenshotAutoCopy && store.settings.overrides == old.overrides)
        store.update { $0.macBookFnControlSwap = true }
        store.applyRecommendedPreset()
        #expect(SettingsStore(defaults: defaults).settings.macBookFnControlSwap)
        #expect(!store.settings.screenshotAutoCopy && store.settings.overrides["my.remote"] == .remoteWindows)
    }
    @Test func removedSwitcherPreferencesDoNotEraseOtherSchemaThreeChoices() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = Data(#"{"schemaVersion":3,"enabled":true,"overrides":{"custom.remote":"remoteWindows"},"screenshotAutoCopy":false,"finderEnabled":true,"altF4Enabled":true,"windowSwitcherEnabled":true,"windowThumbnailsEnabled":true}"#.utf8)
        defaults.set(legacy, forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults, portableHost: false)
        #expect(store.settings.schemaVersion == 6)
        #expect(store.settings.finderEnabled && store.settings.altF4Enabled)
        #expect(!store.settings.screenshotAutoCopy)
        #expect(store.settings.overrides["custom.remote"] == .remoteWindows)
        store.update { $0.textNavigationEnabled = false }
        let data = try #require(defaults.data(forKey: "bridge.settings.v1"))
        let migrated = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(migrated["windowSwitcherEnabled"] == nil)
        #expect(migrated["windowThumbnailsEnabled"] == nil)
    }
    @Test func removedQuitLastWindowPreferenceCannotReenableApplicationQuit() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"schemaVersion":4,"enabled":true,"overrides":{},"altF4Enabled":true,"altF4QuitLastWindow":true}"#.utf8),
                     forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults, portableHost: false)
        store.update { $0.finderEnabled = true }
        let encoded = try #require(defaults.data(forKey: "bridge.settings.v1"))
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["altF4QuitLastWindow"] == nil)
        #expect(store.settings.altF4Enabled && store.settings.finderEnabled)
    }
}
