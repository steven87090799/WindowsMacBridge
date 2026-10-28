import Testing
@testable import BridgeCore

struct DestinationAppSwitchTests {
    @Test func rightAltReleaseAndInvalidationReleaseTheMatchingCommandSide() {
        var state = ModifierStateMachine(); state.reset()
        state.observe(.rightCommand, down: true, aggregate: .command)
        var latch = NativeAppSwitchLatch()
        let down = KeyboardEvent(.down, keyCode: 48, modifiers: .command)
        let translated = EventDecision.rewrite(keyCode: 48, modifiers: .command, ruleID: "windows.nativeAppSwitch")
        let first = latch.apply(translated, event: down, state: state, target: 17)
        #expect(first == translated)
        #expect(latch.isActive(for: 17))
        #expect(!latch.isActive(for: 18))
        let up = KeyboardEvent(.flagsChanged, keyCode: 54, modifiers: [], modifierSide: .rightCommand, modifierDown: false)
        let result = latch.apply(.passThrough, event: up, state: state, target: 17)
        #expect(result == .rewrite(keyCode: 54, modifiers: [], ruleID: "windows.nativeAppSwitch.modifier"))
        #expect(!latch.isActive(for: 17))
        _ = latch.apply(translated, event: down, state: state, target: 17)
        var releases: [UInt16] = []; latch.drain { key, _, pid in releases.append(key); #expect(pid == 17) }
        latch.drain { _,_,_ in Issue.record("Duplicate modifier release") }
        #expect(releases == [54])
    }
    @Test func physicalOptionHeldAtAltReleaseIsNotRemovedFromFlags() {
        var state = ModifierStateMachine(); state.reset()
        state.observe(.leftCommand, down: true, aggregate: .command)
        var latch = NativeAppSwitchLatch()
        let translated = EventDecision.rewrite(keyCode: 48, modifiers: .command, ruleID: "windows.nativeAppSwitch")
        _ = latch.apply(translated, event: .init(.down, keyCode: 48, modifiers: .command), state: state, target: 17)
        let result = latch.apply(.passThrough, event: .init(.flagsChanged, keyCode: 55, modifiers: .option,
            modifierSide: .leftCommand, modifierDown: false), state: state, target: 17)
        #expect(result == .rewrite(keyCode: 55, modifiers: .option, ruleID: "windows.nativeAppSwitch.modifier"))
    }
}
