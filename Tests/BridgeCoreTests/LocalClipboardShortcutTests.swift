import Testing
@testable import BridgeCore

struct LocalClipboardShortcutTests {
    private let chords: [(UInt16, UInt16, String)] = [
        (8, 6, "copy"), (9, 25, "paste"), (0, 4, "selectAll"), (7, 27, "cut")
    ]
    private func processor(_ mode: ApplicationMode) -> KeyboardEventProcessor {
        var p = KeyboardEventProcessor()
        p.configure(context: .init(processID: 17, bundleID: "test.local", mode: mode),
                    enabled: true, layoutSupported: true)
        p.reconcileNeutralHardware()
        return p
    }

    @Test func controlClipboardChordsWorkInMacOSTerminalAndIDEForEitherHand() {
        for mode: ApplicationMode in [.macOS, .terminal, .ide] {
            for right in [false, true] {
                for (key, _, name) in chords {
                    var p = processor(mode)
                    _ = p.process(.init(.flagsChanged, keyCode: right ? 62 : 59, modifiers: .control,
                        modifierSide: right ? .rightControl : .leftControl, modifierDown: true))
                    let conditionalCopy = mode == .terminal && key == 8
                    let output: EventDecision = conditionalCopy ? .action(.terminalCopyOrInterrupt, ruleID: "terminal.copyOrInterrupt") :
                        .rewrite(keyCode: key, modifiers: .command, ruleID: "windows.\(name)")
                    #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == output)
                    #expect(p.process(.init(.down, keyCode: key, modifiers: .control, isRepeat: true)) == (conditionalCopy ? .suppress : output))
                    _ = p.process(.init(.flagsChanged, keyCode: right ? 62 : 59,
                        modifierSide: right ? .rightControl : .leftControl, modifierDown: false))
                    #expect(p.process(.init(.up, keyCode: key)) == (conditionalCopy ? .suppress : .rewrite(keyCode: key, modifiers: [], ruleID: "windows.\(name)")))
                    #expect(p.activePressCount == 0)
                }
            }
        }
    }

    @Test func nativeCommandAndWindowsGuestClipboardChordsRemainUnchanged() {
        for mode in ApplicationMode.allCases {
            for (key, _, _) in chords {
                var p = processor(mode)
                _ = p.process(.init(.flagsChanged, keyCode: 55, modifiers: .command,
                    modifierSide: .leftCommand, modifierDown: true))
                #expect(p.process(.init(.down, keyCode: key, modifiers: .command)) == .passThrough)
                #expect(p.process(.init(.up, keyCode: key, modifiers: .command)) == .passThrough)
                if [.remoteWindows, .virtualMachine, .game, .disabled].contains(mode) {
                    p = processor(mode)
                    _ = p.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                        modifierSide: .leftControl, modifierDown: true))
                    #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == .passThrough)
                    #expect(p.process(.init(.up, keyCode: key, modifiers: .control)) == .passThrough)
                }
            }
        }
    }

    @Test func terminalUsesFullWindowsControlsAndAnExplicitInterruptChord() {
        var p = processor(.terminal)
        _ = p.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
            modifierSide: .leftControl, modifierDown: true))
        for (key, ruleID): (UInt16, String) in [(2,"karabiner.47"),(6,"windows.undo"),(15,"karabiner.45"),(37,"karabiner.44"),(13,"karabiner.25"),(1,"windows.save")] {
            let expected = EventDecision.rewrite(keyCode: key, modifiers: .command, ruleID: ruleID)
            #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == expected)
            #expect(p.process(.init(.up, keyCode: key, modifiers: .control)) == expected)
        }
        _ = p.process(.init(.flagsChanged, keyCode: 56, modifiers: [.control, .shift],
            modifierSide: .leftShift, modifierDown: true))
        let interrupt = EventDecision.rewrite(keyCode: 8, modifiers: .control, ruleID: "terminal.interrupt")
        #expect(p.process(.init(.down, keyCode: 8, modifiers: [.control, .shift])) == interrupt)
        #expect(p.process(.init(.up, keyCode: 8, modifiers: [.control, .shift])) == interrupt)
    }

    @Test func deviceHIDUsesTheSameLocalClipboardRulesAndPreservesRawTransport() {
        for mode: ApplicationMode in [.terminal, .ide] {
            for (key, usage, _) in chords {
                for transportOnly in [false, true] {
                    var e = HIDTranslationEngine(); _ = e.register(1)
                    e.configure(context: .init(processID: 17, mode: mode), layoutSupported: true,
                        finderEnabled: false, transportOnly: transportOnly)
                    _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
                    let action = e.observe(device: 1, page: 7, usage: usage, down: true)
                    let conditionalCopy = mode == .terminal && key == 8 && !transportOnly
                    #expect(action == (conditionalCopy ? .terminalCopyOrInterrupt : nil))
                    var out = HIDOutput()
                    let rendered = e.render(into: &out)
                    #expect(rendered)
                    #expect(out.modifiers == (conditionalCopy ? 0 : (transportOnly ? 1 : 8)))
                    #expect(out.keys.prefix(out.keyCount).contains(usage) == !conditionalCopy)
                    _ = e.observe(device: 1, page: 7, usage: usage, down: false)
                    let released = e.render(into: &out)
                    #expect(released && out.keyCount == 0 && out.modifiers == 1)
                    // The raw report is translated only on the receiving Mac.
                    if transportOnly {
                        var p = processor(mode)
                        p.reconcileIndependentSourceFlags(.control)
                        #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) != .passThrough)
                    }
                }
            }
        }
    }

    @Test func deviceHIDPreservesWindowsGuestClipboardAndPairsTerminalInterrupt() {
        for mode: ApplicationMode in [.remoteWindows, .virtualMachine, .game, .disabled] {
            for (_, usage, _) in chords {
                var e = HIDTranslationEngine(); _ = e.register(1)
                e.configure(context: .init(processID: 17, mode: mode), layoutSupported: true, finderEnabled: false)
                _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
                _ = e.observe(device: 1, page: 7, usage: usage, down: true)
                var out = HIDOutput(); let rendered = e.render(into: &out)
                #expect(rendered && out.modifiers == 1 && out.keys[0] == usage)
            }
        }
        var e = HIDTranslationEngine(); _ = e.register(1)
        e.configure(context: .init(processID: 17, mode: .terminal), layoutSupported: true, finderEnabled: false)
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 1, page: 7, usage: 0xe1, down: true)
        _ = e.observe(device: 1, page: 7, usage: 6, down: true)
        var out = HIDOutput(); let rendered = e.render(into: &out)
        #expect(rendered && out.modifiers == 1 && out.keys[0] == 6)
        _ = e.observe(device: 1, page: 7, usage: 6, down: false)
        let released = e.render(into: &out)
        #expect(released && out.keyCount == 0 && out.modifiers == 3)
    }

    @Test func localWindowsProfilesTranslateControlsAndRetainSafetyGates() {
        for mode: ApplicationMode in [.terminal, .ide] {
            var p = processor(mode)
            p.reconcileIndependentSourceFlags(.control)
            for (key, ruleID): (UInt16, String) in [(2,"karabiner.47"),(6,"windows.undo"),(15,"karabiner.45"),(37,"karabiner.44"),(13,"karabiner.25"),(1,"windows.save")] {
                let expected = EventDecision.rewrite(keyCode: key, modifiers: .command, ruleID: ruleID)
                #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == expected)
                #expect(p.process(.init(.up, keyCode: key, modifiers: .control)) == expected)
            }
            var forwarded = KeyboardEvent(.down, keyCode: 8, modifiers: .control)
            forwarded.allowsTranslation = false
            #expect(p.process(forwarded) == .passThrough)
            _ = p.process(.init(.up, keyCode: 8, modifiers: .control))
            p.configure(context: .init(processID: 17, bundleID: "test.local", mode: mode), enabled: false, layoutSupported: true)
            p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
            #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
        }
    }
}
