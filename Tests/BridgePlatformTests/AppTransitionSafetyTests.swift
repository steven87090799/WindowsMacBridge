import Testing
import BridgeCore
@testable import BridgePlatform

struct AppTransitionSafetyTests {
    private func configuration(_ coordinator: inout RuntimePolicyCoordinator, _ input: RuntimePolicyInput) -> EngineConfiguration {
        var value = EngineConfiguration()
        let snapshot = coordinator.transition(input)
        value.context = input.foreground; value.generation = snapshot.generation
        value.runtimePolicy = snapshot; value.enabled = snapshot.permitsInput
        value.layoutSupported = input.layoutSupported; value.physicalBackend = input.backend
        value.keyboardScope = input.deviceScope
        return value
    }
    @Test func onlyConsecutiveAppTransitionsPreservePhysicalModifiers() {
        for backend: InputBackend in [.eventTap, .deviceHID] {
            var coordinator = RuntimePolicyCoordinator(); var input = RuntimePolicyInput()
            input.shortcutEnabled = true; input.backend = backend
            input.foreground = .init(processID: 17, bundleID: "editor.a", mode: .macOS)
            let first = configuration(&coordinator, input)
            input.foreground = .init(processID: 18, bundleID: "editor.b", mode: .macOS)
            let next = configuration(&coordinator, input)
            #expect(next.preservesModifiers(from: first))
            #expect(!first.preservesModifiers(from: first))
            var missing = next; missing.runtimePolicy = nil
            #expect(!missing.preservesModifiers(from: first))
            var changed = next; changed.finderEnabled = true
            #expect(!changed.preservesModifiers(from: first))
            changed = next; changed.deviceInputs = [.init(identity: "device", experience: .nativeMac)]
            #expect(!changed.preservesModifiers(from: first))
            // An intermediate transition must not disappear when the mailbox coalesces.
            input.paused = true; _ = configuration(&coordinator, input)
            input.paused = false; input.foreground.processID = 19
            #expect(!configuration(&coordinator, input).preservesModifiers(from: next))
        }
    }
    @Test func lifecyclePermissionsSettingsAndNativeOwnershipNeverUseAppContinuity() {
        let mutations: [(inout RuntimePolicyInput) -> Void] = [
            { $0.paused = true }, { $0.secureInput = true }, { $0.session += 1 },
            { $0.sessionActive = false }, { $0.backend = .deviceHID },
            { $0.deviceScope = .builtInAndApple834 }, { $0.manualPassThrough = true },
            { $0.accessibility = false }, { $0.posting = false }, { $0.settingsRevision += 1 },
            { $0.restartToken += 1 }, { $0.hidReleasePending = true },
            { $0.nativeRestorePending = true }, { $0.layoutIdentity = "other" },
            { $0.layoutSupported = false }, { $0.screenshotEnabled = true },
            { $0.shortcutEnabled = false }, { $0.diagnosticsEnabled = true },
            { $0.foreground.mode = .remoteWindows }, { $0.foreground.processID = 0 }
        ]
        for mutation in mutations {
            var coordinator = RuntimePolicyCoordinator(); var input = RuntimePolicyInput()
            input.shortcutEnabled = true
            input.foreground = .init(processID: 17, bundleID: "editor.a", mode: .macOS)
            let first = configuration(&coordinator, input)
            input.foreground = .init(processID: 18, bundleID: "editor.b", mode: .macOS)
            mutation(&input)
            #expect(!configuration(&coordinator, input).preservesModifiers(from: first))
        }
    }
    @Test func coalescedAppChangesKeepControlButIntermediateSecurityGapsCannotDisappear() {
        var coordinator = RuntimePolicyCoordinator(); var input = RuntimePolicyInput()
        input.shortcutEnabled = true
        input.foreground = .init(processID: 17, bundleID: "editor.a", mode: .macOS)
        let first = configuration(&coordinator, input)
        input.foreground = .init(processID: 18, bundleID: "editor.b", mode: .macOS)
        _ = configuration(&coordinator, input) // Mailbox need not observe this App.
        input.foreground = .init(processID: 19, bundleID: "editor.c", mode: .macOS)
        let latest = configuration(&coordinator, input)
        #expect(latest.preservesModifiers(from: first))
        input.secureInput = true; _ = configuration(&coordinator, input)
        input.secureInput = false; input.foreground.processID = 20
        let afterSecure = configuration(&coordinator, input)
        #expect(!afterSecure.preservesModifiers(from: latest))
        input.foreground.mode = .remoteWindows; _ = configuration(&coordinator, input)
        input.foreground = .init(processID: 21, bundleID: "editor.d", mode: .macOS)
        #expect(!configuration(&coordinator, input).preservesModifiers(from: afterSecure))
    }
    @Test func coalescedRoundTripToTheSameAppStillPreservesPhysicalModifiers() {
        var coordinator = RuntimePolicyCoordinator(); var input = RuntimePolicyInput()
        input.shortcutEnabled = true
        input.foreground = .init(processID: 17, bundleID: "editor.a", mode: .macOS)
        let first = configuration(&coordinator, input)
        input.foreground = .init(processID: 18, bundleID: "editor.b", mode: .macOS)
        _ = configuration(&coordinator, input)
        input.foreground = first.context
        let latest = configuration(&coordinator, input)
        #expect(latest.generation > first.generation)
        #expect(latest.preservesModifiers(from: first))
    }
}
