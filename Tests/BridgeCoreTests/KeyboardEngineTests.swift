import Testing
@testable import BridgeCore

struct KeyboardEngineTests {
    private func engine(_ mode: ApplicationMode = .macOS, bundle: String = "test.app") -> KeyboardEventProcessor {
        var p = KeyboardEventProcessor()
        p.configure(context: .init(processID: 10, bundleID: bundle, mode: mode),
                    enabled: true, layoutSupported: true)
        p.reconcileNeutralHardware()
        return p
    }
    private func ctrlDown(_ p: inout KeyboardEventProcessor) {
        _ = p.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                            modifierSide: .leftControl, modifierDown: true))
    }
    @Test func testDefaultChordsAndPairedRelease() {
        for (key, output, id) in [(UInt16(8), UInt16(8), "copy"), (7, 7, "cut"), (9, 9, "paste"),
                                  (0, 0, "selectAll"), (6, 6, "undo"), (1, 1, "save"),
                                  (3, 3, "find"), (35, 35, "print"), (16, 6, "redo")] {
            var p = engine(); ctrlDown(&p)
            let flags: Modifiers = id == "redo" ? [.command, .shift] : .command
            let expected = EventDecision.rewrite(keyCode: output, modifiers: flags, ruleID: "windows.\(id)")
            #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == expected)
            #expect(p.process(.init(.down, keyCode: key, modifiers: .control, isRepeat: true)) == expected)
            #expect(p.process(.init(.up, keyCode: key, modifiers: .control)) == expected)
            #expect(p.activePressCount == 0)
        }
    }
    @Test func testProtectedProfilesNeverTranslate() {
        for mode in ApplicationMode.allCases where mode != .macOS {
            var p = engine(mode); ctrlDown(&p)
            for key: UInt16 in [8, 7, 9, 0, 6, 15, 37, 13, 32, 40, 14, 48] {
                #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == .passThrough)
                #expect(p.process(.init(.up, keyCode: key, modifiers: .control)) == .passThrough)
            }
            #expect(p.process(.init(.down, keyCode: 48, modifiers: .option)) == .passThrough)
        }
    }
    @Test func testExactModifiersAndNativeCommandPreserved() {
        for flags: Modifiers in [.command, [.control, .shift], [.control, .option], [.control, .command], .fn] {
            var p = engine()
            #expect(p.process(.init(.down, keyCode: 8, modifiers: flags)) == .passThrough)
        }
    }
    @Test func testReleaseDoesNotResurrectSyntheticModifier() {
        var p = engine(); ctrlDown(&p)
        _ = p.process(.init(.down, keyCode: 16, modifiers: .control))
        _ = p.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false))
        #expect(p.process(.init(.up, keyCode: 16)) == .rewrite(keyCode: 6, modifiers: [], ruleID: "windows.redo"))
    }
    @Test func testRemoteTransitionDoesNotReceiveLocalRepeatOrRelease() {
        var p = engine(); ctrlDown(&p)
        _ = p.process(.init(.down, keyCode: 8, modifiers: .control))
        p.configure(context: .init(processID: 20, bundleID: "remote", mode: .remoteWindows), enabled: true, layoutSupported: true)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true)) == .suppress)
        #expect(p.process(.init(.up, keyCode: 8, modifiers: .control)) == .suppress)
        #expect(p.process(.init(.down, keyCode: 9, modifiers: .control)) == .passThrough)
    }
    @Test func testReturningLocalWhileControlHeldWaitsForNeutral() {
        var p = engine(.remoteWindows); ctrlDown(&p)
        p.configure(context: .init(processID: 30, bundleID: "local", mode: .macOS), enabled: true, layoutSupported: true)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
        _ = p.process(.init(.up, keyCode: 8, modifiers: .control))
        _ = p.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false))
        ctrlDown(&p)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
    }
    @Test func testReturningToOriginalAppCannotReviveHeldTranslation() {
        var p = engine(); ctrlDown(&p)
        _ = p.process(.init(.down, keyCode: 8, modifiers: .control))
        p.configure(context: .init(processID: 20, bundleID: "remote", mode: .remoteWindows), enabled: true, layoutSupported: true)
        p.configure(context: .init(processID: 10, bundleID: "test.app", mode: .macOS), enabled: true, layoutSupported: true)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true)) == .suppress)
        #expect(p.process(.init(.up, keyCode: 8)) == .suppress)
    }
    @Test func testPausePairsExistingDownButStopsRepeat() {
        var p = engine(); ctrlDown(&p)
        _ = p.process(.init(.down, keyCode: 16, modifiers: .control))
        p.configure(context: .init(processID: 10, bundleID: "test.app", mode: .macOS), enabled: false, layoutSupported: true)
        #expect(p.process(.init(.down, keyCode: 16, modifiers: .control, isRepeat: true)) == .suppress)
        #expect(p.process(.init(.up, keyCode: 16, modifiers: .control)) == .rewrite(keyCode: 6, modifiers: [.command, .shift], ruleID: "windows.redo"))
    }
    @Test func testInputSourceTransitionRequiresReleaseBeforeNewTranslations() {
        var p = engine(); ctrlDown(&p)
        _ = p.process(.init(.down, keyCode: 8, modifiers: .control))
        let local = ApplicationContext(processID: 10, bundleID: "test.app", mode: .macOS)
        p.configure(context: local, enabled: true, layoutSupported: false)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true)) == .suppress)
        #expect(p.process(.init(.up, keyCode: 8, modifiers: .control)) == .rewrite(
            keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        p.configure(context: local, enabled: true, layoutSupported: true)
        #expect(p.process(.init(.down, keyCode: 9, modifiers: .control)) == .passThrough)
        _ = p.process(.init(.up, keyCode: 9, modifiers: .control))
        _ = p.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false))
        ctrlDown(&p)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .rewrite(
            keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
    }
    @Test func testEmergencyPauseConsumesItsPairEvenInRemote() {
        var p = engine(.remoteWindows)
        let flags: Modifiers = [.control, .option, .command]
        #expect(p.process(.init(.down, keyCode: 35, modifiers: flags)) == .emergencyPause)
        #expect(p.process(.init(.down, keyCode: 35, modifiers: flags, isRepeat: true)) == .suppress)
        #expect(p.process(.init(.up, keyCode: 35)) == .suppress)
    }
    @Test func testOwnEventsDoNotChangeStateOrRecurse() {
        var p = engine()
        for _ in 0..<1000 {
            #expect(p.process(.init(.down, keyCode: 8, modifiers: .control, isOwnEvent: true)) == .passThrough)
        }
        #expect(p.processedCount == 0)
        #expect(p.activePressCount == 0)
    }
    @Test func testMissingUpAndRecoveryTombstone() {
        var p = engine(); ctrlDown(&p)
        _ = p.process(.init(.down, keyCode: 8, modifiers: .control))
        p.invalidate()
        #expect(p.process(.init(.up, keyCode: 8)) == .suppress)
        p.reconcileNeutralHardware()
        #expect(p.activePressCount == 0)
        #expect(p.modifiers.synchronized)
    }
    @Test func testBothControlSidesReleaseIndependently() {
        var state = ModifierStateMachine()
        state.observe(.leftControl, down: true, aggregate: .control)
        state.observe(.rightControl, down: true, aggregate: .control)
        state.observe(.leftControl, down: false, aggregate: .control)
        #expect(!state.isDown(.leftControl))
        #expect(state.isDown(.rightControl))
        #expect(state.synchronized)
        state.observe(.rightControl, down: false, aggregate: [])
        #expect(state.synchronized)
        state.observe(.leftShift, down: true, aggregate: [])
        #expect(!state.synchronized)
    }
    @Test func testMissingModifierDownDoesNotTranslate() {
        var p = engine()
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
        #expect(!p.modifiers.synchronized)
    }
    @Test func testRecoveryDoesNotSwallowPreviouslyPassedKeyUp() {
        var p = engine(.terminal)
        #expect(p.process(.init(.down, keyCode: 0)) == .passThrough)
        p.invalidate()
        #expect(p.process(.init(.up, keyCode: 0)) == .passThrough)
        #expect(p.activePressCount == 0)
    }
    @Test func testUnknownLayoutAndFinderCutPassThrough() {
        var p = engine(bundle: "com.apple.finder"); ctrlDown(&p)
        #expect(p.process(.init(.down, keyCode: 7, modifiers: .control)) == .passThrough)
        p = engine()
        p.configure(context: .init(processID: 10, bundleID: "test.app", mode: .macOS), enabled: true, layoutSupported: false)
        p.reconcileNeutralHardware()
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
    }
    @Test func testDuplicateRulesRejected() throws {
        let rule = ShortcutRule(id: "test", input: .init(keyCode: 8, modifiers: .control), output: .init(keyCode: 8, modifiers: .command))
        #expect(throws: RuleCompilationError.duplicateShortcut) {
            try RuleEngine(rules: [rule, rule])
        }
    }
    @Test func testRecoveryCircuitBreaker() {
        var p = RecoveryPolicy()
        let outcomes = [p.mayRetry(at: 100), p.mayRetry(at: 101), p.mayRetry(at: 102), p.mayRetry(at: 161)]
        #expect(outcomes == [true, true, false, true])
    }
    @Test func testOneHundredTwentyThousandEventsRemainBalanced() {
        var p = engine(); ctrlDown(&p)
        for _ in 0..<60_000 {
            #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
            _ = p.process(.init(.up, keyCode: 8, modifiers: .control))
        }
        #expect(p.activePressCount == 0)
        #expect(p.translatedCount == 60_000)
        #expect(p.processedCount == 120_001)
    }
}
