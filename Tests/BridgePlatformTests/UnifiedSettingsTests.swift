import Foundation
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor struct UnifiedSettingsTests {
    @Test func macBookControlRemainsControlAndGlobeIsPreservedByDefault() {
        let name = "unified-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, portableHost: true)
        #expect(!store.settings.macBookFnControlSwap)
    }
    @Test func globalRoleMigratesAwayAndProfilesPersistIndependently() throws {
        let name = "unified-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"schemaVersion":4,"enabled":true,"overrides":{},"remoteInputProfile":"alreadyTranslated","inputBackend":"eventTap"}"#.utf8), forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults, portableHost: true)
        #expect(store.settings.enabled && store.settings.inputBackend == .eventTap)
        store.update {
            $0.remoteSources = [.init(identity: "google", semantics: .alreadyTranslated, transport: .googleRemoteDesktop, learned: true)]
            $0.deviceInputs = [.init(identity: "keyboard1", experience: .nativeMac)]
        }
        let next = SettingsStore(defaults: defaults, portableHost: false)
        #expect(next.settings.remoteSources == store.settings.remoteSources)
        #expect(next.settings.deviceInputs == store.settings.deviceInputs)
        let data = try #require(defaults.data(forKey: "bridge.settings.v1"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["remoteInputProfile"] == nil)
        store.applyRecommendedPreset()
        #expect(store.settings.remoteSources == next.settings.remoteSources && store.settings.deviceInputs == next.settings.deviceInputs)
    }
    @Test func profileBoundsFailClosedWithoutOverwritingData() throws {
        let name = "unified-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var value = BridgeSettings()
        value.remoteSources = (0..<33).map { .init(identity: "source\($0)") }
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: "bridge.settings.v1")
        let store = SettingsStore(defaults: defaults)
        #expect(!store.settings.enabled && store.errorMessage != nil)
        #expect(defaults.data(forKey: "bridge.settings.v1") == data)
    }
    @Test func remoteAndDevicePreferencesNeverAdvanceUnrelatedPhysicalPolicy() {
        var settings = BridgeSettings(); let before = settings.physicalPolicySettings
        settings.remoteSources = [.init(identity: "a", semantics: .alreadyTranslated)]
        settings.deviceInputs = [.init(identity: "keyboard1", experience: .nativeMac)]
        #expect(settings.physicalPolicySettings == before)
        settings.screenshotAutoCopy = false
        #expect(settings.physicalPolicySettings != before)
    }
}
