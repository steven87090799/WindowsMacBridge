import Testing
@testable import BridgeCore

struct InstallReadinessRegressionTests {
    @Test func remoteCoalescedRoundTripRetainsEdgesAndCancelsEarlierWork() {
        let producer = RemoteProducer(processID: 42, identity: "remote", session: 1, revision: 1,
                                      transport: .generic, confidence: .known, semantics: .windows,
                                      independentFlags: false)
        let evidence = InputOriginEvidence(processID: 42, stateID: 0)
        let routing = InputRoutingSnapshot(producers: [producer])
        var configuration = SourceTranslationConfiguration()
        configuration.context = .init(processID: 17, bundleID: "editor.a", mode: .macOS)
        configuration.enabled = true; configuration.layoutSupported = true; configuration.generation = 1
        var router = RemoteSourceRouter(); router.update(routing, configuration: configuration)
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                 modifierSide: .leftControl, modifierDown: true), evidence: evidence)
        let previous = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
        _ = router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence)
        // A -> B -> A is coalesced. The receiver sees the same App with a newer generation.
        configuration.generation = 3
        router.update(routing, configuration: configuration, preservingModifiersOnAppChange: true)
        #expect(previous.validity?.isCurrent == false && producer.work.isCurrent)
        #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence).decision ==
                .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
    }
    @Test func heldControlCanStartANewCopyAfterReceivingAppChanges() {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: 17, bundleID: "editor.a", mode: .macOS),
                            enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                    modifierSide: .leftControl, modifierDown: true))
        let copy = EventDecision.rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy")
        #expect(processor.process(.init(.down, keyCode: 8, modifiers: .control)) == copy)
        _ = processor.process(.init(.up, keyCode: 8, modifiers: .control))
        // An App-only transition drains old outputs but retains observed physical
        // edges. Lifecycle gaps still call invalidate() and require neutral input.
        processor.drainTranslatedReleases { _, _, _ in Issue.record("Previous C was already released") }
        processor.configure(context: .init(processID: 18, bundleID: "editor.b", mode: .macOS),
                            enabled: true, layoutSupported: true, preservingModifiersOnAppChange: true)
        processor.reconcileIndependentSourceFlags(.control)
        #expect(processor.process(.init(.down, keyCode: 8, modifiers: .control)) == copy)
    }

    @Test func appChangeDrainsOldShortcutWithoutRevivingItOrLosingEitherControlSide() {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: 17, bundleID: "editor.a", mode: .macOS),
                            enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        for (key, side): (UInt16, ModifierSide) in [(59, .leftControl), (62, .rightControl)] {
            _ = processor.process(.init(.flagsChanged, keyCode: key, modifiers: .control,
                                        modifierSide: side, modifierDown: true))
        }
        _ = processor.process(.init(.down, keyCode: 8, modifiers: .control))
        var released = 0
        processor.drainTranslatedReleases { key, flags, pid in
            #expect(key == 8 && flags == .command && pid == 17); released += 1
        }
        processor.configure(context: .init(processID: 18, bundleID: "editor.b", mode: .macOS),
                            enabled: true, layoutSupported: true, preservingModifiersOnAppChange: true)
        #expect(released == 1)
        #expect(processor.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true)) == .suppress)
        #expect(processor.process(.init(.down, keyCode: 124, modifiers: .control)) ==
                .rewrite(keyCode: 124, modifiers: .option, ruleID: "karabiner.33"))
        _ = processor.process(.init(.up, keyCode: 124, modifiers: .control))
        #expect(processor.process(.init(.up, keyCode: 8, modifiers: .control)) == .suppress)
        _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                    modifierSide: .leftControl, modifierDown: false))
        #expect(processor.modifiers.isDown(.rightControl) && !processor.modifiers.isDown(.leftControl))
        #expect(processor.process(.init(.down, keyCode: 8, modifiers: .control)) ==
                .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        _ = processor.process(.init(.up, keyCode: 8, modifiers: .control))
        _ = processor.process(.init(.flagsChanged, keyCode: 62, modifiers: [],
                                    modifierSide: .rightControl, modifierDown: false))
        #expect(processor.modifiers.aggregate.isEmpty && processor.activePressCount == 0)
    }

    @Test func appChangeCannotBypassInvalidatedOrChangedShortcutPolicy() {
        for gap in 0..<4 {
            var processor = KeyboardEventProcessor()
            processor.configure(context: .init(processID: 17, bundleID: "editor.a", mode: .macOS),
                                enabled: true, layoutSupported: true)
            processor.reconcileNeutralHardware()
            _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                        modifierSide: .leftControl, modifierDown: true))
            if gap == 0 { processor.invalidate() }
            if gap == 1 {
                // Conflicting side/aggregate evidence represents a missed input edge.
                _ = processor.process(.init(.flagsChanged, keyCode: 56, modifiers: .control,
                                            modifierSide: .leftShift, modifierDown: true))
            }
            processor.configure(context: .init(processID: 18, bundleID: "editor.b", mode: gap == 3 ? .remoteWindows : .macOS),
                                enabled: true, layoutSupported: true, finderEnabled: gap == 2,
                                preservingModifiersOnAppChange: true)
            processor.reconcileIndependentSourceFlags(.control)
            #expect(processor.process(.init(.down, keyCode: 8, modifiers: .control)) == .passThrough)
        }
    }

    @Test func remoteAppChangePreservesOnlyTheSameProducerAndRevokesDetachedWork() {
        for independent in [false, true] {
            let producer = RemoteProducer(processID: 42, identity: "remote", session: 1, revision: 1,
                                          transport: .generic, confidence: .known, semantics: .windows,
                                          independentFlags: independent)
            let evidence = InputOriginEvidence(processID: 42, stateID: 0)
            let routing = InputRoutingSnapshot(producers: [producer])
            var configuration = SourceTranslationConfiguration()
            configuration.context = .init(processID: 17, bundleID: "editor.a", mode: .macOS)
            configuration.enabled = true; configuration.layoutSupported = true; configuration.generation = 1
            var router = RemoteSourceRouter(); router.update(routing, configuration: configuration)
            _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                     modifierSide: .leftControl, modifierDown: true), evidence: evidence)
            let previous = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
            _ = router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence)
            configuration.context = .init(processID: 18, bundleID: "editor.b", mode: .macOS)
            configuration.generation = 2
            router.update(routing, configuration: configuration, preservingModifiersOnAppChange: true)
            #expect(previous.validity?.isCurrent == false && producer.work.isCurrent)
            #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence).decision ==
                    .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
            _ = router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence)
            let changedProducer = RemoteProducer(processID: 42, identity: "remote", session: 2, revision: 1,
                                                 transport: .generic, confidence: .known, semantics: .windows,
                                                 independentFlags: independent)
            configuration.context.processID = 19; configuration.generation = 3
            router.update(.init(producers: [changedProducer]), configuration: configuration,
                          preservingModifiersOnAppChange: true)
            #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence).decision == .passThrough)
        }
    }
}
