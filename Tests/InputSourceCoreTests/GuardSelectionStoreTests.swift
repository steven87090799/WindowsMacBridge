import Foundation
import Testing
@testable import InputSourceCore

struct GuardSelectionStoreTests {
    @Test func legacyPreservedEnglishCannotBecomeExplicitIntent() {
        let name = "GuardSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("com.apple.keylayout.ABC", forKey: "inputSource.preservedSourceIdentifier")
        #expect(GuardSelectionStore(defaults: defaults).desired == .vChewing)
    }

    @Test func explicitEnglishSurvivesRelaunchUntilExplicitTraditionalRequest() {
        let name = "GuardSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        GuardSelectionStore(defaults: defaults).recordRequest(.abc)
        let relaunched = GuardSelectionStore(defaults: defaults)
        #expect(GuardStateMachine(desired: relaunched.desired).desired == .abc)
        relaunched.recordRequest(.vChewing)
        #expect(GuardSelectionStore(defaults: defaults).desired == .vChewing)
    }

    @Test func invalidOrMissingTargetDefaultsToTraditional() {
        let name = "GuardSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = GuardSelectionStore(defaults: defaults)
        #expect(store.desired == .vChewing)
        defaults.set("thirdParty", forKey: "inputSource.guardDesiredSource")
        #expect(store.desired == .vChewing)
    }
}
