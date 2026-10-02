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
        for mode: ApplicationMode in [.remoteWindows, .virtualMachine, .game, .disabled] {
            configuration.context.mode = mode
            #expect(configuration.usesNativePhysicalMapping)
        }
        configuration.context.mode = .macOS; configuration.deviceInputs = [.init(identity: "native", experience: .nativeMac)]
        #expect(configuration.usesNativePhysicalMapping)
    }
}
