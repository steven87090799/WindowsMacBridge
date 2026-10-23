import CoreGraphics
import IOKit.hidsystem
import Testing
import BridgeCore
@testable import BridgePlatform

struct ModifierInputTests {
    @Test func groupNeutralDoesNotRepairAnAlreadyUntrustedPhysicalState() {
        var state = ModifierStateMachine()
        state.observe(.leftControl, down: true, aggregate: .control)
        state.invalidate()
        state.observe(.rightControl, down: false, aggregate: .shift)
        #expect(!state.synchronized && state.aggregate.isEmpty)
    }

    @Test func independentEdgesPreserveEverySideAndIgnoreOwnOutput() {
        for side in ModifierSide.allCases {
            var processor = KeyboardEventProcessor()
            processor.reconcileNeutralHardware()
            _ = processor.processIndependentSource(.init(.flagsChanged, keyCode: 0,
                modifiers: side.group, modifierSide: side, modifierDown: true))
            #expect(processor.modifiers.isDown(side) && !processor.modifiers.isDown(side.peer))
            _ = processor.processIndependentSource(.init(.flagsChanged, keyCode: 0,
                isOwnEvent: true, modifierSide: side, modifierDown: false))
            #expect(processor.modifiers.isDown(side))
            _ = processor.processIndependentSource(.init(.flagsChanged, keyCode: 0,
                modifierSide: side, modifierDown: false))
            #expect(processor.modifiers.synchronized && processor.modifiers.aggregate.isEmpty)
        }
    }

    @Test func aggregateOnlyPeerReleaseClearsTheGroupWhileAnotherModifierRemainsHeld() {
        for first: ModifierSide in [.leftControl, .rightControl] {
            var state = ModifierStateMachine()
            state.observe(.leftShift, down: true, aggregate: .shift)
            for side in [first, first.peer, first] {
                state.observe(side, down: InputEngine.modifierDown(side, flags: [.maskControl, .maskShift]),
                    aggregate: [.control, .shift])
            }
            state.observe(first.peer, down: false, aggregate: .shift)
            #expect(state.synchronized)
            #expect(state.aggregate == .shift)
            #expect(!state.isDown(first) && !state.isDown(first.peer))
        }
    }

    @Test func independentDestinationDoesNotInventLeftOptionBeforeRightOptionShortcut() {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: 1, bundleID: "editor", mode: .macOS),
            enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        for _ in 0..<2 {
            _ = processor.processIndependentSource(.init(.flagsChanged, keyCode: 61, modifiers: .option,
                modifierSide: .rightOption, modifierDown: true))
        }
        #expect(processor.modifiers.isDown(.rightOption))
        #expect(!processor.modifiers.isDown(.leftOption))
        #expect(processor.processIndependentSource(.init(.down, keyCode: 35, modifiers: .option)) == .togglePassThrough)
    }

    @Test func everyNativeModifierSideUsesTheSDKDeviceBits() {
        let sides: [(ModifierSide, CGEventFlags, Int32, Int32)] = [
            (.leftControl, .maskControl, NX_DEVICELCTLKEYMASK, NX_DEVICERCTLKEYMASK),
            (.rightControl, .maskControl, NX_DEVICERCTLKEYMASK, NX_DEVICELCTLKEYMASK),
            (.leftShift, .maskShift, NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK),
            (.rightShift, .maskShift, NX_DEVICERSHIFTKEYMASK, NX_DEVICELSHIFTKEYMASK),
            (.leftCommand, .maskCommand, NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK),
            (.rightCommand, .maskCommand, NX_DEVICERCMDKEYMASK, NX_DEVICELCMDKEYMASK),
            (.leftOption, .maskAlternate, NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK),
            (.rightOption, .maskAlternate, NX_DEVICERALTKEYMASK, NX_DEVICELALTKEYMASK)
        ]
        for (side, group, own, peer) in sides {
            let held = CGEventFlags(rawValue: group.rawValue | UInt64(own))
            let released = CGEventFlags(rawValue: group.rawValue | UInt64(peer))
            #expect(InputEngine.modifierDown(side, flags: held))
            #expect(InputEngine.modifierDown(side, flags: held))
            #expect(!InputEngine.modifierDown(side, flags: released))
            #expect(!InputEngine.modifierDown(side, flags: []))
        }
    }
    @Test func duplicateControlDownsFromUCDoNotInvalidateClipboardShortcuts() {
        // Observed on this MacBook: two flagsChanged(key=59, control=true)
        // precede C, with HID-state PID=0/state=1 and a TextEdit recipient.
        // Exercise both native side flags and aggregate-only transport flags.
        for raw: UInt64 in [0x40001, 0x40000] {
            for key: UInt16 in [8, 7, 9, 0] {
                var processor = KeyboardEventProcessor()
                processor.configure(context: .init(processID: 69062, bundleID: "com.apple.TextEdit", mode: .macOS),
                    enabled: true, layoutSupported: true)
                processor.reconcileNeutralHardware()
                for _ in 0..<2 {
                    let down = InputEngine.modifierDown(.leftControl, flags: .init(rawValue: raw))
                    _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                        modifierSide: .leftControl, modifierDown: down))
                }
                #expect(processor.modifiers.synchronized)
                let decision = processor.process(.init(.down, keyCode: key, modifiers: .control))
                guard case .rewrite(_, .command, _) = decision else {
                    Issue.record("Duplicate Control downs rejected clipboard key \(key): \(decision)")
                    continue
                }
                _ = processor.process(.init(.up, keyCode: key, modifiers: .control))
                for _ in 0..<2 {
                    let down = InputEngine.modifierDown(.leftControl, flags: [])
                    _ = processor.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: down))
                }
                #expect(processor.modifiers.synchronized && processor.modifiers.aggregate.isEmpty)
                #expect(processor.activePressCount == 0)
            }
        }
    }
    @Test func nativeSideBitsDistinguishReleaseWhilePeerControlRemainsDown() {
        var state = ModifierStateMachine()
        for (side, raw, expected): (ModifierSide, UInt64, Bool) in [
            (.leftControl, 0x40001, true), (.rightControl, 0x42001, true),
            (.leftControl, 0x42000, false), (.rightControl, 0, false)
        ] {
            let flags = CGEventFlags(rawValue: raw)
            let down = InputEngine.modifierDown(side, flags: flags)
            #expect(down == expected)
            state.observe(side, down: down, aggregate: InputEngine.modifiers(flags))
            #expect(state.synchronized)
        }
        #expect(state.aggregate.isEmpty)
    }
}
