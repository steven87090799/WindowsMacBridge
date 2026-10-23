import Foundation
import Testing
import BridgeCore
import HIDProtocol
@testable import BridgePlatform

@MainActor struct DestinationRuntimeTests {
    @Test func completeWindowsOwnershipEnablesDestinationSemanticsOnly() {
        var configuration = EngineConfiguration(); configuration.physicalBackend = .deviceHID
        configuration.keyboardScope = .allKeyboards
        #expect(configuration.destinationSemantics)
        configuration.deviceInputs = [.init(identity: "native", experience: .nativeMac)]
        #expect(!configuration.destinationSemantics)
        configuration.deviceInputs = []; configuration.physicalBackend = .eventTap
        #expect(!configuration.destinationSemantics)
    }
    @Test func helperCannotAuthorizeSourceSideScreenshotEvenWithCurrentActionEpoch() async {
        let client = HIDBackendClient()
        var configuration = EngineConfiguration(); configuration.enabled = true
        configuration.layoutSupported = true; configuration.physicalBackend = .deviceHID
        configuration.keyboardScope = .allKeyboards; configuration.generation = 1
        configuration.context = .init(processID: .max, bundleID: "com.apple.finder", mode: .macOS)
        var captures = 0; client.onScreenshot = { _ in captures += 1 }
        client.update(configuration, active: true)
        client.performAction("screenshot.region", processID: .max, generation: 1)
        for _ in 0..<20 { await Task.yield() }
        #expect(captures == 0)
        client.stop()
    }
    @Test func rawTransportIgnoresSourceAppButNotPauseOrPhysicalMappingChanges() {
        var a = HIDConfiguration(); a.transportOnly = true; a.enabled = true; a.mode = .macOS
        var b = a; b.processID = 99; b.bundleID = "com.apple.Terminal"; b.mode = .terminal
        b.layoutSupported = true; b.finderEnabled = true; b.generation = 42
        #expect(a.sameCapturePolicy(as: b))
        b.mode = .ide; #expect(a.sameCapturePolicy(as: b))
        b.enabled = false; #expect(!a.sameCapturePolicy(as: b))
        b = a; b.sessionActive.toggle(); #expect(!a.sameCapturePolicy(as: b))
        b = a; b.macBookFnControlSwap.toggle(); #expect(!a.sameCapturePolicy(as: b))
        b = a; b.transportOnly = false; #expect(!a.sameCapturePolicy(as: b))
        b = a; b.mode = .remoteWindows; #expect(!a.sameCapturePolicy(as: b))
        b = a; b.winTaskViewEnabled.toggle(); #expect(!a.sameCapturePolicy(as: b))
    }
    @Test func nativeFnMappingNeverOverlapsRawHIDCaptureAndRemoteClientsKeepNativeOwnership() {
        var configuration = EngineConfiguration(); configuration.physicalBackend = .deviceHID
        configuration.keyboardScope = .allKeyboards; configuration.context.mode = .terminal
        configuration.layoutSupported = false
        #expect(!configuration.usesNativePhysicalMapping)
        for mode: ApplicationMode in [.remoteWindows, .virtualMachine] {
            configuration.context.mode = mode
            #expect(configuration.usesNativePhysicalMapping)
        }
        configuration.context.mode = .macOS; configuration.deviceInputs = [.init(identity: "native", experience: .nativeMac)]
        #expect(!configuration.usesNativePhysicalMapping)
    }
    @Test func helperKeepsModifiersOnlyWithinAnUninterruptedOwnershipEpoch() throws {
        for transport in [false, true] {
            var a = HIDConfiguration(); a.transportOnly = transport; a.enabled = true; a.sessionActive = true
            a.mode = .macOS; a.processID = 17; a.bundleID = "test.a"; a.generation = 1; a.modifierEpoch = 3
            var b = a; b.mode = .game; b.processID = 18; b.bundleID = "test.b"; b.generation = 2
            b.layoutSupported.toggle()
            #expect(b.preservesModifiers(from: a))
            b.modifierEpoch = 4
            #expect(!b.preservesModifiers(from: a) && !a.sameCapturePolicy(as: b))
            b = a; b.mode = .remoteWindows
            #expect(!b.preservesModifiers(from: a))
            b = a; b.macBookFnControlSwap.toggle()
            #expect(!b.preservesModifiers(from: a))
            b = a; b.modifierEpoch = nil
            #expect(!b.preservesModifiers(from: a))
            // Older hosts omit the optional epoch and retain the conservative handoff.
            let legacy = try JSONDecoder().decode(HIDConfiguration.self, from: JSONEncoder().encode(b))
            #expect(legacy.modifierEpoch == nil && !legacy.preservesModifiers(from: b))
        }
    }
}
