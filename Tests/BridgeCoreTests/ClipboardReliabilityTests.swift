import Testing
@testable import BridgeCore

struct ClipboardReliabilityTests {
    @Test func rejectedFinderPasteRetainsANativeDownRepeatAndReleasePair() {
        var p = KeyboardEventProcessor()
        p.configure(context: .init(processID: 17, bundleID: "com.apple.finder", mode: .macOS),
            enabled: true, layoutSupported: true, finderEnabled: true)
        p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
        #expect(p.process(.init(.down, keyCode: 9, modifiers: .control)) == .action(.finder(.paste), ruleID: "karabiner.64"))
        #expect(p.fallbackForRejectedClipboardAction(keyCode: 9) == .rewrite(keyCode: 9, modifiers: .command, ruleID: "windows.paste"))
        #expect(p.process(.init(.down, keyCode: 9, modifiers: .control, isRepeat: true)) == .rewrite(keyCode: 9, modifiers: .command, ruleID: "windows.paste"))
        p.reconcileIndependentSourceFlags([])
        #expect(p.process(.init(.up, keyCode: 9)) == .rewrite(keyCode: 9, modifiers: [], ruleID: "windows.paste"))
        #expect(p.activePressCount == 0)
    }
    private func render(_ engine: inout HIDTranslationEngine, into output: inout HIDOutput) {
        let success = engine.render(into: &output)
        #expect(success)
    }
    @Test func knownRemoteSourcesShareBasicClipboardRegardlessOfSemanticProfile() {
        for semantics in RemoteSemantics.allCases {
            let producer = RemoteProducer(processID: 77, identity: "test", session: 1, revision: 1,
                transport: .generic, confidence: .known, semantics: semantics, independentFlags: true)
            var configuration = SourceTranslationConfiguration(); configuration.enabled = true
            configuration.layoutSupported = false
            configuration.context = .init(processID: 17, mode: .macOS)
            var router = RemoteSourceRouter(); router.update(.init(producers: [producer]), configuration: configuration)
            let evidence = InputOriginEvidence(processID: 77, stateID: -1)
            _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true), evidence: evidence)
            for key: UInt16 in [8,7,9,0] {
                guard case .rewrite(keyCode: key, modifiers: .command, _) = router.process(.init(.down, keyCode: key, modifiers: .control), evidence: evidence).decision else {
                    Issue.record("Missing remote clipboard: \(semantics), key=\(key)"); continue
                }
                _ = router.process(.init(.up, keyCode: key, modifiers: .control), evidence: evidence)
            }
            _ = router.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false), evidence: evidence)
            #expect(router.process(.init(.down, keyCode: 8, modifiers: .command), evidence: evidence).decision == .passThrough)
        }
    }
    @Test func hidClipboardWorksForEitherControlWithLocalProfilesAndIME() {
        for mode: ApplicationMode in [.macOS, .terminal, .ide, .game, .disabled] {
            for layout in [false, true] {
                for control: UInt16 in [0xe0, 0xe4] {
                    for (key, usage): (UInt16, UInt16) in [(8,6),(7,27),(9,25),(0,4)] {
                        var e = HIDTranslationEngine(); _ = e.register(1)
                        e.configure(context: .init(processID: 17, mode: mode), layoutSupported: layout, finderEnabled: false)
                        _ = e.observe(device: 1, page: 7, usage: control, down: true)
                        #expect(e.observe(device: 1, page: 7, usage: usage, down: true) == nil)
                        var out = HIDOutput()
                        render(&e, into: &out)
                        #expect(out.modifiers == 8 && out.keyCount == 1 && out.keys[0] == usage, "mode=\(mode), layout=\(layout), key=\(key)")
                        _ = e.observe(device: 1, page: 7, usage: usage, down: false)
                        render(&e, into: &out)
                        #expect(out.keyCount == 0 && out.modifiers == (control == 0xe0 ? 1 : 16))
                    }
                }
            }
        }
    }
    @Test func hidFocusChangeRetiresOldOutputAndPreservesHeldControlForNewPaste() {
        var e = HIDTranslationEngine(); _ = e.register(1)
        e.configure(context: .init(processID: 17, mode: .terminal), layoutSupported: true, finderEnabled: false)
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 1, page: 7, usage: 6, down: true)
        e.configure(context: .init(processID: 18, mode: .game), layoutSupported: false, finderEnabled: false,
            preservingModifiersOnAppChange: true)
        var out = HIDOutput(); render(&e, into: &out)
        #expect(out.keyCount == 0 && out.modifiers == 1)
        _ = e.observe(device: 1, page: 7, usage: 25, down: true)
        render(&e, into: &out)
        #expect(out.keyCount == 1 && out.keys[0] == 25 && out.modifiers == 8)
        _ = e.observe(device: 1, page: 7, usage: 6, down: false)
        render(&e, into: &out)
        #expect(out.keyCount == 1 && out.keys[0] == 25 && out.modifiers == 8)
        e.invalidate()
        e.configure(context: .init(processID: 19, mode: .macOS), layoutSupported: true, finderEnabled: false,
            preservingModifiersOnAppChange: true)
        _ = e.observe(device: 1, page: 7, usage: 4, down: true)
        render(&e, into: &out); #expect(out.isEmpty)
    }
    @Test func unknownLocalRecipientAllowsClipboardOnlyEvenBeforeLaunchNotification() throws {
        let foreground = ApplicationContext(processID: 17, bundleID: "com.apple.finder", mode: .macOS)
        let panel = try #require(DestinationSemanticPolicy.context(target: 18, foreground: foreground, recipients: [:]))
        #expect(panel.clipboardOnly)
        var p = KeyboardEventProcessor()
        p.configure(context: panel, enabled: true, layoutSupported: true, finderEnabled: true, screenshotEnabled: true)
        p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        _ = p.process(.init(.up, keyCode: 8, modifiers: .control))
        #expect(p.process(.init(.down, keyCode: 1, modifiers: .control)) == .passThrough)
    }
    @Test func finderPasteWithoutCutIsANativeRewrite() {
        var p = KeyboardEventProcessor()
        p.configure(context: .init(processID: 17, bundleID: "com.apple.finder", mode: .macOS), enabled: true, layoutSupported: true, finderEnabled: true)
        p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
        var event = KeyboardEvent(.down, keyCode: 9, modifiers: .control)
        event.finderMovePending = false
        #expect(p.process(event) == .rewrite(keyCode: 9, modifiers: .command, ruleID: "windows.paste"))
    }
    @Test func heldControlAcrossWindowsGuestAndLocalPanelKeepsNewClipboardPressesWorking() {
        var p = KeyboardEventProcessor()
        p.configure(context: .init(processID: 17, mode: .remoteWindows), enabled: true, layoutSupported: true)
        p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
        _ = p.process(.init(.up, keyCode: 8, modifiers: .control))
        p.configure(context: .init(processID: 18, mode: .macOS), enabled: true, layoutSupported: true, preservingModifiersOnAppChange: true)
        #expect(p.process(.init(.down, keyCode: 9, modifiers: .control)) == .rewrite(keyCode: 9, modifiers: .command, ruleID: "windows.paste"))
        p.invalidate()
        p.configure(context: .init(processID: 19, mode: .macOS), enabled: true, layoutSupported: true, preservingModifiersOnAppChange: true)
        #expect(p.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
    }
    @Test func synchronousCopyRevokesAnOlderCutWithoutErasingANewerCut() {
        let intent = FinderClipboardIntent()
        let first = intent.beginCut(); #expect(intent.isCurrent(first))
        intent.observeCopy(); #expect(!intent.isCurrent(first) && intent.pending == 0)
        let second = intent.beginCut()
        intent.finish(first)
        #expect(intent.isCurrent(second))
        intent.finish(second); #expect(intent.pending == 0)
    }
    @Test func copyIsSynchronousInFinderAndTerminal() {
        for context in [ApplicationContext(processID: 17, bundleID: "com.apple.finder", mode: .macOS),
                        .init(processID: 18, bundleID: "com.apple.Terminal", mode: .terminal)] {
            var p = KeyboardEventProcessor()
            p.configure(context: context, enabled: true, layoutSupported: true, finderEnabled: true)
            p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
            guard case .rewrite(keyCode: 8, modifiers: .command, _) = p.process(.init(.down, keyCode: 8, modifiers: .control)) else {
                Issue.record("Ctrl+C must not depend on an async action or selection query"); continue
            }
            guard case .rewrite(keyCode: 8, modifiers: .command, _) = p.process(.init(.up, keyCode: 8, modifiers: .control)) else {
                Issue.record("Copy release must pair with its native down"); continue
            }
        }
    }
    @Test func clipboardDoesNotDependOnTextLayoutOrLocalAppProfile() {
        for mode: ApplicationMode in [.macOS, .terminal, .ide, .game, .disabled] {
            for layout in [false, true] {
                var p = KeyboardEventProcessor()
                p.configure(context: .init(processID: 17, bundleID: "test.local", mode: mode), enabled: true, layoutSupported: layout)
                p.reconcileNeutralHardware(); p.reconcileIndependentSourceFlags(.control)
                for key: UInt16 in [8, 7, 9, 0] {
                    guard case .rewrite(keyCode: key, modifiers: .command, _) = p.process(.init(.down, keyCode: key, modifiers: .control)) else {
                        Issue.record("Missing clipboard rewrite for \(mode), layout=\(layout), key=\(key)"); continue
                    }
                    _ = p.process(.init(.up, keyCode: key, modifiers: .control))
                }
            }
        }
    }
    @Test func firstRemoteCopyAfterSystemPanelAppearsKeepsHeldControl() {
        let producer = RemoteProducer(processID: 77, identity: "test", session: 1, revision: 1,
            transport: .generic, confidence: .known, semantics: .windows, independentFlags: false)
        let routing = InputRoutingSnapshot(producers: [producer])
        let evidence = InputOriginEvidence(processID: 77, stateID: -1)
        var c = SourceTranslationConfiguration(); c.enabled = true; c.layoutSupported = true
        c.context = .init(processID: 17, bundleID: "com.apple.finder", mode: .macOS)
        c.generation = 1
        var r = RemoteSourceRouter(); r.update(routing, configuration: c)
        _ = r.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true), evidence: evidence)
        c.context = .init(processID: 18, bundleID: "com.apple.screencaptureui", mode: .macOS)
        r.update(routing, configuration: c, preservingModifiersOnAppChange: true)
        #expect(r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence).decision ==
            .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
    }
}
