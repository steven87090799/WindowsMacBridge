import Testing
@testable import BridgeCore

struct DestinationAppSwitchTests {
    @Test func rightAltReleaseAndInvalidationReleaseTheMatchingCommandSide() {
        var state = ModifierStateMachine(); state.reset()
        state.observe(.rightOption, down: true, aggregate: .option)
        var latch = NativeAppSwitchLatch()
        let down = KeyboardEvent(.down, keyCode: 48, modifiers: .option)
        let translated = EventDecision.rewrite(keyCode: 48, modifiers: .command, ruleID: "windows.nativeAppSwitch")
        let first = latch.apply(translated, event: down, state: state, target: 17)
        #expect(first == translated)
        #expect(latch.isActive(for: 17))
        #expect(!latch.isActive(for: 18))
        let up = KeyboardEvent(.flagsChanged, keyCode: 61, modifiers: [], modifierSide: .rightOption, modifierDown: false)
        let result = latch.apply(.passThrough, event: up, state: state, target: 17)
        #expect(result == .rewrite(keyCode: 54, modifiers: [], ruleID: "windows.nativeAppSwitch.modifier"))
        #expect(!latch.isActive(for: 17))
        _ = latch.apply(translated, event: down, state: state, target: 17)
        var releases: [UInt16] = []; latch.drain { key, _, pid in releases.append(key); #expect(pid == 17) }
        latch.drain { _,_,_ in Issue.record("Duplicate modifier release") }
        #expect(releases == [54])
    }
    @Test func physicalCommandHeldAtAltReleaseIsNotRemovedFromFlags() {
        var state = ModifierStateMachine(); state.reset()
        state.observe(.leftOption, down: true, aggregate: .option)
        var latch = NativeAppSwitchLatch()
        let translated = EventDecision.rewrite(keyCode: 48, modifiers: .command, ruleID: "windows.nativeAppSwitch")
        _ = latch.apply(translated, event: .init(.down, keyCode: 48, modifiers: .option), state: state, target: 17)
        let result = latch.apply(.passThrough, event: .init(.flagsChanged, keyCode: 58, modifiers: .command,
            modifierSide: .leftOption, modifierDown: false), state: state, target: 17)
        #expect(result == .rewrite(keyCode: 55, modifiers: .command, ruleID: "windows.nativeAppSwitch.modifier"))
    }
}
