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
    @Test func pendingHIDReleaseGatesEitherBackendUntilItResolves() {
        // VirtualHID output can re-enter a session tap as HID-state input while
        // the old lease is retiring; neither backend may translate until then.
        var input = RuntimePolicyInput()
        input.shortcutEnabled = true; input.hidReleasePending = true
        var policy = RuntimePolicyCoordinator()
        #expect(!policy.transition(input).permitsInput)
        input.backend = .deviceHID
        #expect(!policy.transition(input).permitsInput)
        input.backend = .eventTap; input.hidReleasePending = false
        #expect(policy.transition(input).permitsInput)
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
    @Test func secureInputKeepsTheTapSoItsEndIsObservedWithoutAnAppSwitch() {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true; input.secureInput = true
        var policy = RuntimePolicyCoordinator()
        let secure = policy.transition(input)
        #expect(!secure.permitsInput && secure.awaitsSecureInputEnd)
        var config = EngineConfiguration()
        config.enabled = secure.permitsInput; config.observesSecureInputEnd = secure.awaitsSecureInputEnd
        #expect(config.needsEventTap)
        // Another blocker (pause, permissions, disabled) never keeps a tap for Secure Input.
        for mutation: (inout RuntimePolicyInput) -> Void in [{ $0.paused = true }, { $0.listening = false },
                                                           { $0.shortcutEnabled = false }, { $0.sessionActive = false }] {
            var blocked = input; mutation(&blocked)
            #expect(!policy.transition(blocked).awaitsSecureInputEnd)
        }
        input.secureInput = false
        #expect(!policy.transition(input).awaitsSecureInputEnd && policy.transition(input).permitsInput)
    }
    @Test func normalIdleHasNoWakeTimer() {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: true, deadline: nil) == .stopped)
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: 25) == .deadline(25))
    }
    @Test func normalKeyboardInputRequiresBothControlAndMonitoringGrants() {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true
        var policy = RuntimePolicyCoordinator()
        input.listening = false
        #expect(!policy.transition(input).permitsInput)
        input.listening = true
        #expect(policy.transition(input).permitsInput)
        input.posting = false
        #expect(!policy.transition(input).permitsInput)
        input.posting = true; input.accessibility = false
        #expect(!policy.transition(input).permitsInput)
    }
}
