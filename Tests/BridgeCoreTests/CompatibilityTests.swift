import Foundation
import Testing
@testable import BridgeCore

struct CompatibilityTests {
    private func processor(browser: Bool = false, finder: Bool = false, mode: ApplicationMode = .macOS,
                           windowsKeyModifier: WindowsKeyModifier = .command) -> KeyboardEventProcessor {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: 10, bundleID: finder ? "com.apple.finder" : "test", mode: mode,
                                            isBrowser: browser), enabled: true, layoutSupported: true, finderEnabled: finder,
                            windowsKeyModifier: windowsKeyModifier)
        processor.reconcileNeutralHardware()
        return processor
    }
    private func pressModifiers(_ value: Modifiers, _ processor: inout KeyboardEventProcessor, right: Bool = false) {
        var held: Modifiers = []
        for (group, left, rightSide, key) in [(Modifiers.control, ModifierSide.leftControl, ModifierSide.rightControl, UInt16(59)),
                                              (.option, .leftOption, .rightOption, 58),
                                              (.command, .leftCommand, .rightCommand, 55),
                                              (.shift, .leftShift, .rightShift, 56)] where value.contains(group) {
            held.insert(group)
            _ = processor.process(.init(.flagsChanged, keyCode: key, modifiers: held,
                                         modifierSide: right ? rightSide : left, modifierDown: true))
        }
    }
    @Test func generalAndBrowserChordsPairForBothHands() {
        for right in [false, true] {
            for (browser, rules) in [(false, WindowsCompatibilityRules.general), (true, WindowsCompatibilityRules.browser)] {
                for rule in rules {
                    var p = processor(browser: browser)
                    pressModifiers(rule.input.modifiers, &p, right: right)
                    let expected = EventDecision.rewrite(keyCode: rule.output.keyCode,
                                                        modifiers: rule.output.modifiers, ruleID: rule.id)
                    #expect(p.process(.init(.down, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers)) == expected)
                    #expect(p.process(.init(.down, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers, isRepeat: true)) == expected)
                    #expect(p.process(.init(.up, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers)) == expected)
                    #expect(p.activePressCount == 0)
                }
            }
        }
    }
    @Test func browserScopeAndOptionConsumption() {
        var normal = processor(); pressModifiers(.control, &normal)
        #expect(normal.process(.init(.down, keyCode: 17, modifiers: .control)) == .passThrough)
        var browser = processor(browser: true); pressModifiers(.option, &browser)
        #expect(browser.process(.init(.down, keyCode: 123, modifiers: .option)) ==
                .rewrite(keyCode: 33, modifiers: .command, ruleID: "karabiner.50"))
        _ = browser.process(.init(.flagsChanged, keyCode: 58, modifierSide: .leftOption, modifierDown: false))
        #expect(browser.process(.init(.up, keyCode: 123)) == .rewrite(keyCode: 33, modifiers: [], ruleID: "karabiner.50"))
    }
    @Test func rightOptionToggleIsPairedAndDoesNotAutorepeat() {
        var p = processor(mode: .remoteWindows); pressModifiers(.option, &p, right: true)
        #expect(p.process(.init(.down, keyCode: 35, modifiers: .option)) == .togglePassThrough)
        #expect(p.manualPassThrough)
        #expect(p.process(.init(.down, keyCode: 35, modifiers: .option, isRepeat: true)) == .suppress)
        #expect(p.process(.init(.up, keyCode: 35, modifiers: .option)) == .suppress)
        _ = p.process(.init(.flagsChanged, keyCode: 61, modifierSide: .rightOption, modifierDown: false))
        pressModifiers(.option, &p, right: true)
        #expect(p.process(.init(.down, keyCode: 35, modifiers: .option)) == .togglePassThrough)
        #expect(!p.manualPassThrough)
        var left = processor(); pressModifiers(.option, &left)
        #expect(left.process(.init(.down, keyCode: 35, modifiers: .option)) == .passThrough)
    }
    @Test func finderActionsConsumeExactlyOnePair() {
        for rule in WindowsCompatibilityRules.finder {
            var p = processor(finder: true); pressModifiers(rule.input.modifiers, &p)
            let down = p.process(.init(.down, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers))
            if let action = rule.action {
                #expect(down == .action(action, ruleID: rule.id))
                #expect(p.process(.init(.down, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers, isRepeat: true)) == .suppress)
                #expect(p.process(.init(.up, keyCode: rule.input.keyCode)) == .suppress)
            } else {
                #expect(down == .rewrite(keyCode: rule.output.keyCode, modifiers: rule.output.modifiers, ruleID: rule.id))
                _ = p.process(.init(.up, keyCode: rule.input.keyCode))
            }
            #expect(p.activePressCount == 0)
        }
    }
    @Test func systemActionsRespectSideAndRemoteProtection() {
        for mode in ApplicationMode.allCases {
            var p = processor(mode: mode, windowsKeyModifier: .option); pressModifiers(.option, &p)
            let result = p.process(.init(.down, keyCode: 14, modifiers: .option))
            if mode == .macOS {
                #expect(result == .action(.system(.openFinder), ruleID: "karabiner.12"))
            } else { #expect(result == .passThrough) }
        }
        var right = processor(windowsKeyModifier: .option); pressModifiers(.option, &right, right: true)
        #expect(right.process(.init(.down, keyCode: 14, modifiers: .option)) == .passThrough)
    }
    @Test func fileCutOnlyMovesOnceAndExpiresOnMetadataChanges() {
        var cut = FinderCutState()
        #expect(cut.consume(changeCount: 1, finderPID: 100, now: 0) == false)
        cut.arm(changeCount: 3, finderPID: 100, now: 0)
        #expect(cut.consume(changeCount: 3, finderPID: 100, now: 1) == true)
        #expect(cut.consume(changeCount: 3, finderPID: 100, now: 2) == false)
        for (count, pid, now) in [(4, Int32(100), 1.0), (3, 101, 1), (3, 100, 300)] {
            cut.arm(changeCount: 3, finderPID: 100, now: 0)
            #expect(cut.validate(changeCount: count, finderPID: pid, now: now) == false)
            #expect(cut.consume(changeCount: 3, finderPID: 100, now: 2) == false)
        }
        cut.arm(changeCount: 3, finderPID: 100, now: 0); cut.cancel()
        #expect(cut.consume(changeCount: 3, finderPID: 100, now: 1) == false)
    }
    @Test func unsupportedDeviceScopeCannotSilentlyBecomeGlobal() {
        #expect(!BackendCapabilities.eventTap.canReplaceRequestedProfile)
        #expect(!BackendCapabilities.eventTap.supports(.builtInAndApple834))
        #expect(BackendCapabilities.eventTap.supports(.allKeyboards))
        #expect(KeyboardDevice(registryID: 1, builtIn: true, vendorID: 0, productID: 0).matchesRequestedScope)
        #expect(KeyboardDevice(registryID: 2, builtIn: false, vendorID: 1452, productID: 834).matchesRequestedScope)
        #expect(!KeyboardDevice(registryID: 3, builtIn: false, vendorID: 1452, productID: 999).matchesRequestedScope)
        #expect(!KeyboardDevice(registryID: 4, builtIn: false, vendorID: 1452, productID: 834, isKeyboard: false).matchesRequestedScope)
    }
    @Test func mixedShortcutStressHasBoundedLedger() {
        var p = processor(browser: true)
        for i in 0..<30_000 {
            let rule = WindowsCompatibilityRules.browser[i % WindowsCompatibilityRules.browser.count]
            p.reconcileNeutralHardware()
            pressModifiers(rule.input.modifiers, &p)
            _ = p.process(.init(.down, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers))
            _ = p.process(.init(.down, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers, isRepeat: true))
            _ = p.process(.init(.up, keyCode: rule.input.keyCode, modifiers: rule.input.modifiers))
            #expect(p.activePressCount == 0)
        }
        #expect(p.processedCount >= 120_000)
        #expect(p.translatedCount == 30_000)
    }
}
