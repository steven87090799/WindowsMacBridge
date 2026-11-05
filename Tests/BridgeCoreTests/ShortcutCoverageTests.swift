import Testing
@testable import BridgeCore

struct ShortcutCoverageTests {
    private struct Binding {
        var app: String
        var key: UInt16
        var input: Modifiers = .control
        var output: UInt16
        var flags: Modifiers = .command
    }
    private let bindings: [Binding] = [
        .init(app: "text", key: 11, output: 11), .init(app: "text", key: 34, output: 34),
        .init(app: "text", key: 32, output: 32),
        .init(app: "text", key: 6, input: [.control, .shift], output: 6, flags: [.command, .shift]),
        .init(app: "text", key: 9, input: [.control, .shift], output: 9, flags: [.command, .option, .shift]),
        .init(app: "text", key: 114, output: 8), .init(app: "text", key: 114, input: .shift, output: 9),
        .init(app: "text", key: 126, output: 126, flags: .option),
        .init(app: "text", key: 125, input: [.control, .shift], output: 125, flags: [.option, .shift]),
        .init(app: "text", key: 4, output: 3, flags: [.command, .option]),
        .init(app: "text", key: 118, output: 13), .init(app: "chrome", key: 5, output: 5),
        .init(app: "chrome", key: 4, output: 16), .init(app: "chrome", key: 38, output: 38, flags: [.command, .shift]),
        .init(app: "chrome", key: 2, input: .command, output: 37),
        .init(app: "chrome", key: 40, output: 37),
        .init(app: "chrome", key: 9, input: [.control, .shift], output: 9, flags: [.command, .shift]),
        .init(app: "chrome", key: 32, output: 32, flags: [.command, .option]),
        .init(app: "chrome", key: 117, input: [.control, .shift], output: 51, flags: [.command, .shift]),
        .init(app: "chrome", key: 96, input: [], output: 15),
        .init(app: "chrome", key: 96, input: .shift, output: 15, flags: [.command, .shift]),
        .init(app: "chrome", key: 99, input: [], output: 5),
        .init(app: "chrome", key: 103, input: [], output: 3, flags: [.control, .command]),
        .init(app: "chrome", key: 111, input: [], output: 34, flags: [.command, .option]),
        .init(app: "chrome", key: 34, input: [.control, .shift], output: 34, flags: [.command, .option]),
        .init(app: "firefox", key: 4, output: 4, flags: [.command, .shift]),
        .init(app: "firefox", key: 38, output: 38),
        .init(app: "firefox", key: 103, input: [], output: 3, flags: [.command, .shift]),
        .init(app: "firefox", key: 40, output: 40),
        .init(app: "firefox", key: 14, output: 40),
        .init(app: "firefox", key: 96, output: 15, flags: [.command, .shift]),
        .init(app: "firefox", key: 115, input: .command, output: 115, flags: .option),
        .init(app: "firefox", key: 31, input: [.control, .shift], output: 31, flags: [.command, .shift]),
        .init(app: "firefox", key: 117, input: [.control, .shift], output: 51, flags: [.command, .shift]),
        .init(app: "firefox", key: 34, input: [.control, .shift], output: 34, flags: [.command, .option]),
        .init(app: "firefox", key: 40, input: [.control, .shift], output: 40, flags: [.command, .option]),
        .init(app: "firefox", key: 38, input: [.control, .shift], output: 38, flags: [.command, .shift]),
        .init(app: "firefox", key: 8, input: [.control, .shift], output: 8, flags: [.command, .option]),
        .init(app: "edge", key: 38, output: 37, flags: [.command, .option]),
        .init(app: "opera", key: 38, output: 38),
        .init(app: "opera", key: 4, output: 4, flags: [.command, .shift]),
        .init(app: "opera", key: 32, output: 32),
        .init(app: "vivaldi", key: 2, input: [.control, .shift], output: 37, flags: [.command, .option]),
        .init(app: "safari", key: 38, output: 37, flags: [.command, .option]),
        .init(app: "safari", key: 15, input: [.control, .shift], output: 15, flags: [.command, .option]),
        .init(app: "finder", key: 3, output: 3), .init(app: "finder", key: 17, output: 17),
        .init(app: "finder", key: 36, input: .command, output: 34),
        .init(app: "finder", key: 118, output: 13)
    ]
    private func context(_ app: String) -> ApplicationContext {
        let bundles = ["text": "com.apple.TextEdit", "chrome": "com.google.Chrome",
            "firefox": "org.mozilla.firefox", "safari": "com.apple.Safari", "finder": "com.apple.finder",
            "edge": "com.microsoft.edgemac", "opera": "com.operasoftware.Opera", "vivaldi": "com.vivaldi.Vivaldi"]
        return .init(processID: 100, bundleID: bundles[app]!, mode: .macOS,
            isBrowser: ["chrome", "firefox", "safari", "edge", "opera", "vivaldi"].contains(app))
    }
    private func policy(_ context: ApplicationContext) -> SourceTranslationConfiguration {
        var c = SourceTranslationConfiguration()
        c.context = context; c.enabled = true; c.layoutSupported = true
        c.finderEnabled = true; c.altF4Enabled = true; c.screenshotEnabled = true
        return c
    }
    private let sides: [(UInt16, ModifierSide, UInt16)] = [
        (59, .leftControl, 0xe0), (56, .leftShift, 0xe1), (58, .leftOption, 0xe2), (55, .leftCommand, 0xe3)
    ]
    private func verify(_ result: EventDecision, binding b: Binding) {
        guard case .rewrite(let key, let flags, _) = result else {
            Issue.record("Missing rewrite in \(b.app): \(b.key)/\(b.input): \(result)"); return
        }
        #expect(key == b.output && flags == b.flags, "\(b.app) key=\(b.key) input=\(b.input.rawValue) output=\(key)/\(flags.rawValue), expected=\(b.output)/\(b.flags.rawValue)")
    }
    @Test func commonShortcutsPairAcrossEventTapHIDAndBothGooglePolicies() {
        for b in bindings {
            let app = context(b.app)
            var local = KeyboardEventProcessor()
            local.configure(context: app, enabled: true, layoutSupported: true, finderEnabled: true)
            local.reconcileNeutralHardware(); local.reconcileIndependentSourceFlags(b.input)
            verify(local.process(.init(.down, keyCode: b.key, modifiers: b.input)), binding: b)
            verify(local.process(.init(.up, keyCode: b.key, modifiers: b.input)), binding: b)
            #expect(local.activePressCount == 0)

            var hid = HIDTranslationEngine(); _ = hid.register(1)
            hid.configure(context: app, layoutSupported: true, finderEnabled: true)
            for (_, side, usage) in sides where b.input.contains(side.group) {
                _ = hid.observe(device: 1, page: 7, usage: usage, down: true)
            }
            let usage = HIDKeyMap.usage[Int(b.key)]!
            #expect(hid.observe(device: 1, page: 7, usage: usage, down: true) == nil)
            var report = HIDOutput()
            let rendered = hid.render(into: &report)
            #expect(rendered)
            let expectedBits: UInt8 = (b.flags.contains(.control) ? 1 : 0) | (b.flags.contains(.shift) ? 2 : 0) |
                (b.flags.contains(.option) ? 4 : 0) | (b.flags.contains(.command) ? 8 : 0)
            #expect(report.modifiers == expectedBits && report.keyCount == 1 && report.keys[0] == HIDKeyMap.usage[Int(b.output)], "HID \(b.app) key=\(b.key) input=\(b.input.rawValue)")
            _ = hid.observe(device: 1, page: 7, usage: usage, down: false)
            for (_, side, usage) in sides where b.input.contains(side.group) {
                _ = hid.observe(device: 1, page: 7, usage: usage, down: false)
            }
            _ = hid.render(into: &report); #expect(report.isEmpty)

            for semantics: RemoteSemantics in [.automatic, .windows] {
                // Automatic mode must not reinterpret already-native Command chords.
                if semantics == .automatic && b.input.contains(.command) { continue }
                var router = RemoteSourceRouter()
                router.update(.init(producers: [.init(processID: 42, identity: "google", session: 1, revision: 1,
                    transport: .googleRemoteDesktop, confidence: .known, semantics: semantics, independentFlags: true)]), configuration: policy(app))
                let evidence = InputOriginEvidence(processID: 42, stateID: -1)
                _ = router.process(.init(.flagsChanged, keyCode: 59), evidence: evidence)
                var flags: Modifiers = []
                for (key, side, _) in sides where b.input.contains(side.group) {
                    flags.insert(side.group)
                    _ = router.process(.init(.flagsChanged, keyCode: key, modifiers: flags, modifierSide: side, modifierDown: true), evidence: evidence)
                }
                for phase: KeyPhase in [.down, .up] {
                    verify(router.process(.init(phase, keyCode: b.key, modifiers: b.input), evidence: evidence).decision, binding: b)
                }
            }
        }
    }
    @Test func contextualHomeEndAndParagraphsNeverBorrowBrowserHistoryOrMissionControl() {
        for app in ["chrome", "finder"] {
            for (key, flags, action): (UInt16, Modifiers, TextNavigationAction) in [
                (115, [], .home), (119, [], .end), (115, .shift, .selectHome), (119, .shift, .selectEnd),
                (126, .control, .paragraphUp), (125, [.control, .shift], .selectParagraphDown)
            ] {
                var p = KeyboardEventProcessor()
                p.configure(context: context(app), enabled: true, layoutSupported: true, finderEnabled: true)
                p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(flags)
                #expect(p.process(.init(.down, keyCode: key, modifiers: flags)) ==
                    .action(.textNavigation(action), ruleID: "text.contextual." + action.rawValue))
                #expect(p.process(.init(.up, keyCode: key, modifiers: flags)) == .suppress)
                var hid = HIDTranslationEngine(); _ = hid.register(1)
                hid.configure(context: context(app), layoutSupported: true, finderEnabled: true)
                for (_, side, usage) in sides where flags.contains(side.group) { _ = hid.observe(device: 1, page: 7, usage: usage, down: true) }
                #expect(hid.observe(device: 1, page: 7, usage: HIDKeyMap.usage[Int(key)]!, down: true) == .textNavigation(action))
            }
        }
        #expect(TextNavigationAction.home.output(textFocused: false) == .init(keyCode: 115, modifiers: []))
        #expect(TextNavigationAction.end.output(textFocused: false) == .init(keyCode: 119, modifiers: []))
        #expect(TextNavigationAction.home.output(textFocused: true) == .init(keyCode: 123, modifiers: .command))
        #expect(TextNavigationAction.selectEnd.output(textFocused: true) == .init(keyCode: 124, modifiers: [.command, .shift]))
        #expect(TextNavigationAction.paragraphUp.output(textFocused: false) == nil)
    }
    @Test func googleAutomaticAcceptsOnlyUnambiguousWindowsAltChordsAndKeepsNativeMacKeys() {
        for transport: RemoteTransport in [.googleRemoteDesktop, .vnc] {
            for confidence: InputConfidence in [.known, .unknown] {
                for key: UInt16 in [118, 105, 8, 1, 2] {
                    var router = RemoteSourceRouter()
                    router.update(.init(producers: [.init(processID: 42, identity: "host", session: 1, revision: 1,
                        transport: transport, confidence: confidence, semantics: .automatic, independentFlags: true)]), configuration: policy(context("chrome")))
                    let evidence = InputOriginEvidence(processID: 42, stateID: -1)
                    _ = router.process(.init(.flagsChanged, keyCode: 55, modifiers: .command, modifierSide: .leftCommand, modifierDown: true), evidence: evidence)
                    let result = router.process(.init(.down, keyCode: key, modifiers: .command), evidence: evidence).decision
                    if transport == .googleRemoteDesktop && confidence == .known && (key == 118 || key == 105) {
                        #expect(result == (key == 118 ? .action(.window(.close), ruleID: "windows.altF4") : .action(.screenshot(.activeWindow), ruleID: "windows.screenshot")))
                    } else { #expect(result == .passThrough) }
                }
            }
        }
    }
    @Test func clipboardAliasesRespectGuestsAndFinderFallbackNeverTurnsPasteIntoCopy() {
        for mode: ApplicationMode in [.remoteWindows, .virtualMachine] {
            var app = context("text"); app.mode = mode
            for flags: Modifiers in [.control, .shift] {
                #expect(ClipboardShortcutPolicy.match(key: 114, modifiers: flags, context: app, finderEnabled: true) == nil)
            }
        }
        var p = KeyboardEventProcessor()
        p.configure(context: context("finder"), enabled: true, layoutSupported: true, finderEnabled: true)
        p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.shift)
        #expect(p.process(.init(.down, keyCode: 114, modifiers: .shift)) == .action(.finder(.paste), ruleID: "karabiner.64"))
        #expect(p.fallbackForRejectedClipboardAction(keyCode: 114) == .rewrite(keyCode: 9, modifiers: .command, ruleID: "windows.paste"))
        #expect(p.process(.init(.up, keyCode: 114, modifiers: .shift)) == .rewrite(keyCode: 9, modifiers: .command, ruleID: "windows.paste"))
    }
    @Test func textNavigationSwitchAndProtectedProfilesApplyToNewRules() {
        for mode: ApplicationMode in [.remoteWindows, .virtualMachine, .game, .disabled] {
            var app = context("chrome"); app.mode = mode
            var p = KeyboardEventProcessor()
            p.configure(context: app, enabled: true, layoutSupported: true)
            p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
            #expect(p.process(.init(.down, keyCode: 11, modifiers: .control)) == .passThrough)
        }
        var p = KeyboardEventProcessor()
        p.configure(context: context("text"), enabled: true, layoutSupported: true, textNavigationEnabled: false)
        p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
        #expect(p.process(.init(.down, keyCode: 126, modifiers: .control)) == .passThrough)
    }
    @Test func newTextFormattingDoesNotReplaceShellBindingsOrMoveSourceLinesInIDEs() {
        for mode: ApplicationMode in [.macOS, .terminal, .ide] {
            var app = context("text"); app.mode = mode
            var p = KeyboardEventProcessor()
            p.configure(context: app, enabled: true, layoutSupported: true)
            p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
            let keys: [UInt16] = mode == .macOS ? [5] : mode == .terminal ? [11, 34, 32, 4, 5, 125, 126] : [5, 125, 126]
            for key in keys {
                #expect(p.process(.init(.down, keyCode: key, modifiers: .control)) == .passThrough)
                _ = p.process(.init(.up, keyCode: key, modifiers: .control))
            }
        }
    }
}
