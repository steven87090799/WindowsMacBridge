import Foundation
import Testing
import BridgeCore
import BridgePlatform

@MainActor struct ModeIsolationTests {
    @Test func oldHIDSettingsDoNotOptIntoPrivilegedMode() throws {
        let legacy = Data(#"{"schemaVersion":5,"enabled":true,"overrides":{},"inputBackend":"deviceHID","keyboardScope":"builtInAndApple834"}"#.utf8)
        let settings = try JSONDecoder().decode(BridgeSettings.self, from: legacy)
        #expect(!settings.isAdvancedModeEnabled)
        #expect(settings.effectiveInputBackend == .eventTap)
        #expect(settings.effectiveKeyboardScope == .allKeyboards)
        #expect(settings.effectiveDeviceInputs.isEmpty)
    }
    @Test func freshInstallIsUserOnlyAndFnSwapIsExplicit() {
        let settings = BridgeSettings()
        #expect(!settings.isAdvancedModeEnabled)
        #expect(settings.inputBackend == .eventTap)
        #expect(settings.finderEnabled && settings.screenshotAutoCopy)
        #expect(!settings.macBookFnControlSwap)
    }
    @Test func lateHIDReleaseCannotDisableEventTap() {
        var input = RuntimePolicyInput()
        input.shortcutEnabled = true; input.hidReleasePending = true
        var policy = RuntimePolicyCoordinator()
        #expect(policy.transition(input).permitsInput)
        input.backend = .deviceHID
        #expect(!policy.transition(input).permitsInput)
    }
    @Test func pauseWhileRestoringFnKeepsOnlyTheReleaseObservationAlive() {
        var config = EngineConfiguration()
        config.enabled = false; config.nativeMappingAwaitingNeutral = true
        #expect(config.needsEventTap)
        config.nativeMappingAwaitingNeutral = false
        #expect(!config.needsEventTap)
        config.nativeMappingAwaitingNeutral = true; config.sessionActive = false
        #expect(!config.needsEventTap)
    }
    @Test func normalIdleHasNoWakeTimer() {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: true, deadline: nil) == .stopped)
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: 25) == .deadline(25))
    }
}
