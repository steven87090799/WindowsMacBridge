import CoreGraphics
import Testing
import BridgeCore
@testable import BridgePlatform

struct NativeSessionEmitterTests {
    @Test func nativeSystemShortcutsReturnToSessionRoutingWithoutPretendingToBePhysicalHID() {
        for rule in ["karabiner.11", "windows.winR", "windows.winTab", "windows.nativeAppSwitch", "windows.nativeAppSwitch.modifier"] {
            #expect(NativeSessionEmitter.requiresSessionRouting(rule))
        }
        #expect(!NativeSessionEmitter.requiresSessionRouting("windows.copy"))
        #expect(!NativeSessionEmitter.requiresSessionRouting("finder.delete"))
        let marker: Int64 = 1234
        let event = NativeSessionEmitter.prepare(type: .keyDown, keyCode: 48, modifiers: .command, marker: marker)
        // -1 requests a private table; CoreGraphics assigns that table a unique
        // positive ID. It must share neither combined-session (0) nor HID (1) state.
        #expect(event?.getIntegerValueField(.eventSourceStateID) != 0)
        #expect(event?.getIntegerValueField(.eventSourceStateID) != 1)
        #expect(event != nil)
        #expect(event?.getIntegerValueField(.eventSourceUserData) == marker)
        #expect(event?.getIntegerValueField(.eventTargetUnixProcessID) == 0)
        #expect(event?.getIntegerValueField(.keyboardEventKeycode) == 48)
        #expect(event?.flags.contains(.maskCommand) == true)
        // Preparation creates an offline CGEvent only. This test never posts input.
    }
    @Test func modifierCleanupUsesFlagsChangedAndTheOriginalCommandSide() {
        let event = NativeSessionEmitter.prepare(type: .flagsChanged, keyCode: 54, modifiers: [], marker: 1234)
        #expect(event?.type == .flagsChanged)
        #expect(event?.getIntegerValueField(.keyboardEventKeycode) == 54)
        #expect(event?.flags.contains(.maskCommand) == false)
    }
}
