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
        #expect(SettingsStore(defaults: defaults).settings == store.settings)
    }

    @Test func removingBundledCodexRuleRestoresTerminalProtection() throws {
        var settings = BridgeSettings()
        settings.overrides.removeValue(forKey: "com.openai.codex")
        #expect(try ApplicationRegistry().mode(for: "com.openai.codex", overrides: settings.overrides) == .ide)
    }
}
