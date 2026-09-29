import Foundation
import Testing
@testable import BridgeCore

struct WindowsFeatureTests {
    @Test func finderPathsPreferSelectedWithoutTouchingClipboard() {
        let target = URL(fileURLWithPath: "/Users/test/Documents")
        let selected = [URL(fileURLWithPath: "/Users/test/Documents/a.txt"),
                        URL(fileURLWithPath: "/Users/test/Documents/b.txt")]
        #expect(FinderPathSelection.folder(targetedURL: target) == "/Users/test/Documents")
        #expect(FinderPathSelection.folder(targetedURL: selected[0], itemTarget: true) == target.path)
        #expect(FinderPathSelection.selected(selected) == "/Users/test/Documents/a.txt\n/Users/test/Documents/b.txt")
        #expect(FinderPathSelection.displayed(selectedURLs: selected, targetedURL: target) == selected[0].path)
        #expect(FinderPathSelection.displayed(selectedURLs: [], targetedURL: target) == target.path)
        #expect(FinderPathSelection.selected([]) == nil)
    }
    @Test func windowCycleCommitsOnlyOnReleaseAndReverses() {
        var cycle = WindowCycle()
        #expect(cycle.selectedIndex == nil)
        cycle.advance(count: 4, reverse: false)
        #expect(cycle.selectedIndex == 1)
        cycle.advance(count: 4, reverse: true)
        #expect(cycle.selectedIndex == 0)
        cycle.advance(count: 4, reverse: true)
        #expect(cycle.selectedIndex == 3)
        #expect(cycle.commit() == 3)
        #expect(cycle.selectedIndex == nil)
        cycle.advance(count: 1, reverse: false)
        #expect(cycle.commit() == 0)
    }
    @Test func focusedWindowHistoryIsPerWindowAndBounded() {
        var history = WindowHistory()
        history.record("10:a"); history.record("10:b"); history.record("20:c")
        #expect(history.rank(of: "20:c") == 0)
        #expect(history.rank(of: "10:b") == 1)
        history.record("10:a")
        #expect(history.rank(of: "10:a") == 0)
        history.remove(processID: 10)
        #expect(history.rank(of: "10:a") == Int.max)
        for id in 0..<300 { history.record("30:\(id)") }
        #expect(history.rank(of: "30:0") == Int.max)
        #expect(history.rank(of: "30:299") == 0)
    }
    @Test func windowSwitchPolicyProtectsRemoteTerminalIDEAndGame() {
        for mode in ApplicationMode.allCases {
            #expect(WindowSwitchPolicy.intercepts(mode: mode, enabled: true, layoutSupported: true,
                                                  inputReady: true, manualPassThrough: false,
                                                  emergencyPaused: false) == (mode == .macOS))
        }
        #expect(!WindowSwitchPolicy.intercepts(mode: .macOS, enabled: true, layoutSupported: true,
                                               inputReady: true,
                                               manualPassThrough: true, emergencyPaused: false))
        #expect(!WindowSwitchPolicy.intercepts(mode: .macOS, enabled: false, layoutSupported: true,
                                               inputReady: true,
                                               manualPassThrough: false, emergencyPaused: false))
        #expect(!WindowSwitchPolicy.intercepts(mode: .macOS, enabled: true, layoutSupported: true,
                                               inputReady: false,
                                               manualPassThrough: false, emergencyPaused: false))
    }
    private func processor(mode: ApplicationMode = .macOS, finder: Bool = false,
                           text: Bool = true, permanentDelete: Bool = false,
                           altF4: Bool = false) -> KeyboardEventProcessor {
        var value = KeyboardEventProcessor()
        value.configure(context: .init(processID: 12, bundleID: finder ? "com.apple.finder" : "test", mode: mode),
                        enabled: true, layoutSupported: true, finderEnabled: finder,
                        finderPermanentDeleteEnabled: permanentDelete,
                        textNavigationEnabled: text, altF4Enabled: altF4)
        value.reconcileNeutralHardware()
        return value
    }
    private func hold(_ modifiers: Modifiers, _ value: inout KeyboardEventProcessor) {
        var active: Modifiers = []
        for (group, side, key) in [(Modifiers.control, ModifierSide.leftControl, UInt16(59)),
                                   (.option, .leftOption, 58), (.shift, .leftShift, 56)] where modifiers.contains(group) {
            active.insert(group)
            _ = value.process(.init(.flagsChanged, keyCode: key, modifiers: active,
                                    modifierSide: side, modifierDown: true))
        }
    }
    @Test func textHomeEndAndSelectionAreIndependentOfOldCtrlRules() {
        for rule in WindowsCompatibilityRules.textNavigation {
            var value = processor()
            hold(rule.input.modifiers, &value)
            #expect(value.process(.init(.down, keyCode: rule.input.keyCode,
                                         modifiers: rule.input.modifiers)) ==
                    .rewrite(keyCode: rule.output.keyCode, modifiers: rule.output.modifiers, ruleID: rule.id))
            _ = value.process(.init(.up, keyCode: rule.input.keyCode))
            #expect(value.activePressCount == 0)
        }
        var disabled = processor(text: false)
        hold(.control, &disabled)
        #expect(disabled.process(.init(.down, keyCode: 123, modifiers: .control)) == .passThrough)
        var terminal = processor(mode: .terminal)
        #expect(terminal.process(.init(.down, keyCode: 115)) == .passThrough)
    }
    @Test func finderExtrasAndPermanentDeleteGate() {
        for rule in WindowsCompatibilityRules.finderExtras {
            var value = processor(finder: true, permanentDelete: true)
            hold(rule.input.modifiers, &value)
            #expect(value.process(.init(.down, keyCode: rule.input.keyCode,
                                         modifiers: rule.input.modifiers)) == .action(rule.action!, ruleID: rule.id))
            #expect(value.process(.init(.up, keyCode: rule.input.keyCode)) == .suppress)
        }
        var disabled = processor(finder: true)
        hold(.shift, &disabled)
        #expect(disabled.process(.init(.down, keyCode: 117, modifiers: .shift)) == .passThrough)
        var remote = processor(mode: .remoteWindows, finder: true, permanentDelete: true)
        #expect(remote.process(.init(.down, keyCode: 117)) == .passThrough)
    }
    @Test func altF4OnlyClosesInLocalModeWhenEnabled() {
        for mode in ApplicationMode.allCases {
            var value = processor(mode: mode, altF4: true)
            hold(.option, &value)
            let result = value.process(.init(.down, keyCode: 118, modifiers: .option))
            if mode == .macOS { #expect(result == .action(.window(.close), ruleID: "windows.altF4")) }
            else { #expect(result == .passThrough) }
        }
        var disabled = processor()
        hold(.option, &disabled)
        #expect(disabled.process(.init(.down, keyCode: 118, modifiers: .option)) == .passThrough)
    }
}
