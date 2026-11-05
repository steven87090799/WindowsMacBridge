import Testing
import BridgeCore

struct WindowsProductionRegressionTests {
    private func context(_ bundle: String) -> ApplicationContext {
        .init(processID: 100, bundleID: bundle, mode: .macOS, isBrowser: bundle != "com.apple.finder")
    }

    private func decision(_ key: UInt16, _ flags: Modifiers, in bundle: String) -> EventDecision {
        var config = ShortcutPreviewConfiguration()
        config.context = context(bundle)
        return ShortcutPreview.evaluate(.init(keyCode: key, modifiers: flags), configuration: config).decision
    }

    @Test func finderDocumentNavigationCannotOpenParentOrSelectedFolder() {
        for (key, textKey): (UInt16, UInt16) in [(115, 126), (119, 125)] {
            for shift: Modifiers in [[], .shift] {
                let result = decision(key, shift.union(.control), in: "com.apple.finder")
                guard case .action(.textNavigation(let action), _) = result else {
                    Issue.record("Finder Ctrl+Home/End must resolve text focus before emitting: \(result)")
                    continue
                }
                #expect(action.output(textFocused: false) == .init(keyCode: key, modifiers: shift))
                #expect(action.output(textFocused: true) == .init(keyCode: textKey, modifiers: shift.union(.command)))
            }
        }
    }

    @Test func finderDocumentNavigationPairsAcrossLocalHIDAndRemoteInput() {
        let app = context("com.apple.finder")
        for (key, action): (UInt16, TextNavigationAction) in [(115, .documentHome), (119, .documentEnd),
            (115, .selectDocumentHome), (119, .selectDocumentEnd)] {
            let shift = action == .selectDocumentHome || action == .selectDocumentEnd
            let flags: Modifiers = shift ? [.control, .shift] : .control
            let expected = EventDecision.action(.textNavigation(action), ruleID: action.ruleID)
            var local = KeyboardEventProcessor()
            local.configure(context: app, enabled: true, layoutSupported: true, finderEnabled: true)
            local.reconcileNeutralHardware(); local.reconcileIndependentSourceFlags(flags)
            #expect(local.process(.init(.down, keyCode: key, modifiers: flags)) == expected)
            #expect(local.process(.init(.up, keyCode: key, modifiers: flags)) == .suppress)
            #expect(local.activePressCount == 0)

            var hid = HIDTranslationEngine(); _ = hid.register(1)
            hid.configure(context: app, layoutSupported: true, finderEnabled: true)
            _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: true)
            if shift { _ = hid.observe(device: 1, page: 7, usage: 0xe1, down: true) }
            let usage = HIDKeyMap.usage[Int(key)]!
            #expect(hid.observe(device: 1, page: 7, usage: usage, down: true) == .textNavigation(action))
            _ = hid.observe(device: 1, page: 7, usage: usage, down: false)
            _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: false)
            if shift { _ = hid.observe(device: 1, page: 7, usage: 0xe1, down: false) }
            var report = HIDOutput()
            let rendered = hid.render(into: &report)
            #expect(rendered && report.isEmpty)

            for semantics: RemoteSemantics in [.automatic, .windows] {
                var config = SourceTranslationConfiguration()
                config.context = app; config.enabled = true; config.layoutSupported = true; config.finderEnabled = true
                var router = RemoteSourceRouter()
                router.update(.init(producers: [.init(processID: 42, identity: "google", session: 1, revision: 1,
                    transport: .googleRemoteDesktop, confidence: .known, semantics: semantics, independentFlags: true)]), configuration: config)
                let evidence = InputOriginEvidence(processID: 42, stateID: -1)
                _ = router.process(.init(.flagsChanged, keyCode: 59), evidence: evidence)
                #expect(router.process(.init(.down, keyCode: key, modifiers: flags), evidence: evidence).decision == expected)
                #expect(router.process(.init(.up, keyCode: key, modifiers: flags), evidence: evidence).decision == .suppress)
            }
        }
    }

    @Test func repairedBrowserAndFinderRulesHonorDisabledNavigationAndGuestProfiles() {
        for key: UInt16 in [115, 119] {
            var config = ShortcutPreviewConfiguration()
            config.context = context("com.apple.finder"); config.textNavigationEnabled = false
            #expect(ShortcutPreview.evaluate(.init(keyCode: key, modifiers: .control), configuration: config).decision == .passThrough)
        }
        for mode: ApplicationMode in [.remoteWindows, .virtualMachine, .game, .disabled] {
            for (key, flags): (UInt16, Modifiers) in [(103, []), (38, .control), (96, .control), (115, .command)] {
                var config = ShortcutPreviewConfiguration()
                config.context = context("org.mozilla.firefox"); config.context.mode = mode
                #expect(ShortcutPreview.evaluate(.init(keyCode: key, modifiers: flags), configuration: config).decision == .passThrough)
            }
        }
    }

    @Test func edgeDownloadsUseEdgeBindingForEveryReleaseChannel() {
        for bundle in ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
                       "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary"] {
            #expect(decision(38, .control, in: bundle) ==
                .rewrite(keyCode: 37, modifiers: [.command, .option], ruleID: "browser.downloads"))
        }
        #expect(decision(38, .control, in: "com.google.Chrome") ==
            .rewrite(keyCode: 38, modifiers: [.command, .shift], ruleID: "browser.downloads"))
    }

    @Test func operaAndVivaldiDoNotInheritConflictingChromeBindings() {
        for (key, flags, output, outputFlags, id): (UInt16, Modifiers, UInt16, Modifiers, String) in [
            (38, .control, 38, .command, "browser.downloads"),
            (4, .control, 4, [.command, .shift], "browser.history"),
            (32, .control, 32, .command, "browser.viewSource")
        ] {
            #expect(decision(key, flags, in: "com.operasoftware.Opera") ==
                .rewrite(keyCode: output, modifiers: outputFlags, ruleID: id))
        }
        #expect(decision(2, [.control, .shift], in: "com.vivaldi.Vivaldi") ==
            .rewrite(keyCode: 37, modifiers: [.command, .option], ruleID: "browser.downloadsPanel"))
    }

    @Test func firefoxUsesItsOwnFullScreenSearchAndHardReloadBindings() {
        let cases: [(UInt16, Modifiers, UInt16, Modifiers, String)] = [
            (103, [], 3, [.command, .shift], "browser.fullScreenF11"),
            (40, .control, 40, .command, "browser.searchCtrlK"),
            (14, .control, 40, .command, "browser.searchCtrlE"),
            (96, .control, 15, [.command, .shift], "browser.reloadIgnoringCache"),
            (115, .command, 115, .option, "browser.homePage"),
            (31, [.control, .shift], 31, [.command, .shift], "browser.bookmarkManager"),
            (117, [.control, .shift], 51, [.command, .shift], "browser.clearData")
        ]
        for bundle in ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"] {
            for (key, input, output, flags, id) in cases {
                #expect(decision(key, input, in: bundle) == .rewrite(keyCode: output, modifiers: flags, ruleID: id))
            }
            // Firefox reserves Shift+F5 for its profiler on both operating systems.
            #expect(decision(96, .shift, in: bundle) == .passThrough)
        }
    }

    private func producer(_ id: Int32) -> RemoteProducer {
        .init(processID: id, identity: "host-\(id)", session: 1, revision: 1,
              transport: .googleRemoteDesktop, confidence: .known, independentFlags: true)
    }

    private func router(_ producers: [RemoteProducer]) -> RemoteSourceRouter {
        var config = SourceTranslationConfiguration()
        config.context = context("com.google.Chrome")
        config.enabled = true; config.layoutSupported = true
        var router = RemoteSourceRouter()
        router.update(.init(producers: producers), configuration: config)
        return router
    }

    private func copy(_ router: inout RemoteSourceRouter, _ evidence: InputOriginEvidence,
                      now: Double, release: Bool) -> RoutedInputDecision {
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
            modifierSide: .leftControl, modifierDown: true), evidence: evidence, now: now)
        let result = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence, now: now)
        if release { finish(&router, evidence, now: now) }
        return result
    }

    private func finish(_ router: inout RemoteSourceRouter, _ evidence: InputOriginEvidence, now: Double) {
        _ = router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence, now: now)
        _ = router.process(.init(.flagsChanged, keyCode: 59,
            modifierSide: .leftControl, modifierDown: false), evidence: evidence, now: now)
    }

    @Test func completedRemoteStreamsCannotPermanentlyExhaustTheRouter() {
        let producers = (1...32).map { producer(Int32($0)) }
        var router = router(producers)
        var first: SourceWorkToken?
        for (i, producer) in producers.enumerated() {
            let result = copy(&router, .init(processID: producer.processID, stateID: -1), now: Double(i), release: true)
            #expect(result.decision == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
            if i == 0 { first = result.validity }
        }
        #expect(first?.isCurrent == false)
        #expect(producers.allSatisfy { $0.work.isCurrent })
        #expect(router.nextExpiry == nil)
        // A single host can also replace its event-source state between sessions.
        for state in 0..<32 {
            let result = copy(&router, .init(processID: 32, stateID: Int64(state)), now: Double(32 + state), release: true)
            #expect(result.decision == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        }
    }

    @Test func aNewRemoteStreamCannotEvictAnyHeldChordButCanReuseItsCompletedSlot() {
        let producers = (1...17).map { producer(Int32($0)) }
        var router = router(producers)
        var held = [SourceWorkToken]()
        for id in 1...16 {
            let result = copy(&router, .init(processID: Int32(id), stateID: -1), now: 0, release: false)
            #expect(result.decision == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
            if let token = result.validity { held.append(token) }
        }
        let next = InputOriginEvidence(processID: 17, stateID: -1)
        #expect(copy(&router, next, now: 1, release: true).decision == .passThrough)
        #expect(held.allSatisfy { $0.isCurrent })
        finish(&router, .init(processID: 1, stateID: -1), now: 2)
        #expect(copy(&router, next, now: 3, release: true).decision ==
            .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        #expect(held.first?.isCurrent == false)
        #expect(held.dropFirst().allSatisfy { $0.isCurrent })
        for id in 2...16 { finish(&router, .init(processID: Int32(id), stateID: -1), now: 4) }
        #expect(router.nextExpiry == nil)
    }
}
