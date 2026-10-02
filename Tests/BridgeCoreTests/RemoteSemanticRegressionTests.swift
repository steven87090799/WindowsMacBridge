import Testing
@testable import BridgeCore

struct RemoteSemanticRegressionTests {
    private func router(semantics: RemoteSemantics = .automatic, independent: Bool = true) -> RemoteSourceRouter {
        var r = RemoteSourceRouter(); var c = SourceTranslationConfiguration()
        c.context = .init(processID: 1, bundleID: "browser", mode: .macOS, isBrowser: true)
        c.enabled = true; c.layoutSupported = true; c.altF4Enabled = true; c.screenshotEnabled = true
        r.update(.init(producers: [.init(processID: 42, identity: "google", session: 1, revision: 1,
                                       transport: .googleRemoteDesktop, confidence: .known, semantics: semantics, independentFlags: independent)]), configuration: c)
        return r
    }
    private let evidence = InputOriginEvidence(processID: 42, stateID: 0)
    private func edge(_ r: inout RemoteSourceRouter, side: ModifierSide, key: UInt16, flags: Modifiers, down: Bool) {
        _ = r.process(.init(.flagsChanged, keyCode: key, modifiers: flags, modifierSide: side, modifierDown: down), evidence: evidence)
    }
    @Test func googleRawWindowsSemanticMatrixPairsEveryDownAndUp() {
        let cases: [(UInt16, Modifiers, UInt16, Modifiers)] = [
            (8,.control,8,.command), (9,.control,9,.command), (7,.control,7,.command), (0,.control,0,.command),
            (6,.control,6,.command), (16,.control,6,[.command,.shift]), (3,.control,3,.command), (1,.control,1,.command),
            (35,.control,35,.command), (13,.control,13,.command), (17,.control,17,.command),
            (17,[.control,.shift],17,[.command,.shift]), (45,.control,45,.command),
            (123,.control,123,.option), (124,.control,124,.option), (123,[.control,.shift],123,[.option,.shift]),
            (124,[.control,.shift],124,[.option,.shift]), (51,.control,51,.option),
            (115,[],123,.command), (119,[],124,.command), (115,.shift,123,[.command,.shift]), (119,.shift,124,[.command,.shift])]
        for (key, input, outputKey, flags) in cases {
            var r = router()
            if input.contains(.control) { edge(&r, side: .leftControl, key: 59, flags: .control, down: true) }
            if input.contains(.shift) { edge(&r, side: .leftShift, key: 56, flags: input, down: true) }
            for phase: KeyPhase in [.down,.up] {
                let decision = r.process(.init(phase, keyCode: key, modifiers: input), evidence: evidence).decision
                guard case .rewrite(let actualKey, let actualFlags, _) = decision else { Issue.record("Missing translation \(key)/\(input) in \(phase)"); continue }
                #expect(actualKey == outputKey && actualFlags == flags)
            }
        }
    }
    @Test func controlAfterCopyOverlappingNavigationAndReleaseOrdersNeverInheritCommand() {
        for releaseControlFirst in [false,true] {
            var r = router(); edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
            _ = r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
            let arrow = r.process(.init(.down, keyCode: 124, modifiers: .control), evidence: evidence)
            #expect(arrow.decision == .rewrite(keyCode: 124, modifiers: .option, ruleID: "karabiner.33"))
            if releaseControlFirst { edge(&r, side: .leftControl, key: 59, flags: [], down: false) }
            _ = r.process(.init(.up, keyCode: 8, modifiers: releaseControlFirst ? [] : .control), evidence: evidence)
            _ = r.process(.init(.up, keyCode: 124, modifiers: releaseControlFirst ? [] : .control), evidence: evidence)
            if !releaseControlFirst {
                #expect(r.process(.init(.down, keyCode: 48, modifiers: .control), evidence: evidence).decision == .passThrough)
                _ = r.process(.init(.up, keyCode: 48, modifiers: .control), evidence: evidence)
                edge(&r, side: .leftControl, key: 59, flags: [], down: false)
            }
            #expect(r.process(.init(.down, keyCode: 0), evidence: evidence).decision == .passThrough)
        }
    }
    @Test func independentFlagsPreserveBothModifierSidesAndReleaseOrder() {
        for leftFirst in [false,true] {
            var r = router()
            edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
            edge(&r, side: .rightControl, key: 62, flags: .control, down: true)
            _ = r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
            edge(&r, side: leftFirst ? .leftControl : .rightControl, key: leftFirst ? 59 : 62, flags: .control, down: false)
            #expect(r.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true), evidence: evidence).decision ==
                    .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
            edge(&r, side: leftFirst ? .rightControl : .leftControl, key: leftFirst ? 62 : 59, flags: [], down: false)
            #expect(r.process(.init(.down, keyCode: 8, isRepeat: true), evidence: evidence).decision == .suppress)
            _ = r.process(.init(.up, keyCode: 8), evidence: evidence)
        }
    }
    @Test func genericOverrideUsesOnlyOwnModifierEdgesEvenWithOtherSourcesFlags() {
        var r = router(semantics: .windows, independent: false)
        edge(&r, side: .leftControl, key: 59, flags: [.control,.shift,.command], down: true)
        #expect(r.process(.init(.down, keyCode: 8, modifiers: [.control,.shift,.command]), evidence: evidence).decision ==
                .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        _ = r.process(.init(.up, keyCode: 8, modifiers: [.control,.shift,.command]), evidence: evidence)
        edge(&r, side: .leftControl, key: 59, flags: [.control,.shift], down: false)
        #expect(r.process(.init(.down, keyCode: 8, modifiers: [.control,.shift]), evidence: evidence).decision == .passThrough)
    }
    @Test func screenshotsAndAXCloseAreActionsAndAlreadyMacChordsPassThrough() {
        var r = router(semantics: .windows)
        edge(&r, side: .leftOption, key: 58, flags: .option, down: true)
        #expect(r.process(.init(.down, keyCode: 118, modifiers: .option), evidence: evidence).decision == .action(.window(.close), ruleID: "windows.altF4"))
        _ = r.process(.init(.up, keyCode: 118, modifiers: .option), evidence: evidence)
        #expect(r.process(.init(.down, keyCode: 105, modifiers: .option), evidence: evidence).decision == .action(.screenshot(.activeWindow), ruleID: "windows.screenshot"))
        _ = r.process(.init(.up, keyCode: 105, modifiers: .option), evidence: evidence)
        edge(&r, side: .leftOption, key: 58, flags: [], down: false)
        for key: UInt16 in [8,9,7,0,6,1,3,13,17,45] {
            #expect(r.process(.init(.down, keyCode: key, modifiers: .command), evidence: evidence).decision == .passThrough)
            _ = r.process(.init(.up, keyCode: key, modifiers: .command), evidence: evidence)
        }
    }
    @Test func lostTransportLeaseReleasesOnlyThatSourceAndCancelsItsWork() {
        var r = router(); edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
        let work = r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence, now: 10)
        var releases = [(UInt16, Modifiers, Int32)]()
        r.expire(at: 71) { releases.append(($0,$1,$2)) }
        #expect(releases.count == 1 && releases[0].0 == 8 && work.validity?.isCurrent == false)
        #expect(r.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true), evidence: evidence, now: 72).decision == .suppress)
        _ = r.process(.init(.up, keyCode: 8), evidence: evidence, now: 73)
        edge(&r, side: .leftControl, key: 59, flags: [], down: false)
        edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
        #expect(r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence, now: 74).decision != .passThrough)
    }
    @Test func boundedSourceStormCannotCreateUnboundedLedgersOrInbox() {
        let inbox = InputProducerInbox()
        for pid: Int32 in 1...10_000 { inbox.observe(pid) }
        #expect(inbox.take().count == 16 && inbox.take().isEmpty)
        var r = router(); edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
        for _ in 0..<20_000 {
            _ = r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
            _ = r.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence)
        }
        var releases = 0; r.invalidate { _,_,_ in releases += 1 }
        #expect(releases == 0 && r.translatedCount == 20_000)
    }
    @Test func rightAltAppSwitchLossReleasesItsCommandSideAndRevokesWork() {
        var r = router()
        #expect(!r.hasNativeAppSwitchSession(evidence))
        edge(&r, side: .rightOption, key: 61, flags: .option, down: true)
        let work = r.process(.init(.down, keyCode: 48, modifiers: .option), evidence: evidence)
        #expect(r.hasNativeAppSwitchSession(evidence))
        #expect(!r.hasNativeAppSwitchSession(.init(processID: 43, stateID: 0)))
        _ = r.process(.init(.up, keyCode: 48, modifiers: .option), evidence: evidence)
        var releases = [UInt16]()
        r.invalidate { key, _, _ in releases.append(key) }
        #expect(!r.hasNativeAppSwitchSession(evidence))
        #expect(releases == [54] && work.validity?.isCurrent == false)
    }
    @Test func hostTransitionsRevokeRemoteJobsAndNeverReviveHeldShortcut() {
        let p = RemoteProducer(processID: 42, identity: "google", session: 1, revision: 1,
                               transport: .googleRemoteDesktop, confidence: .known, independentFlags: true)
        var baseline = SourceTranslationConfiguration(); baseline.enabled = true; baseline.layoutSupported = true
        baseline.context = .init(processID: 1, bundleID: "editor", mode: .macOS)
        var transitions = [SourceTranslationConfiguration]()
        var paused = baseline; paused.enabled = false; transitions.append(paused)
        var secureOrSession = baseline; secureOrSession.enabled = false; secureOrSession.generation = 2; transitions.append(secureOrSession)
        var backendOrGeneration = baseline; backendOrGeneration.generation = 3; transitions.append(backendOrGeneration)
        var appSwitch = baseline; appSwitch.context = .init(processID: 2, bundleID: "other", mode: .macOS); transitions.append(appSwitch)
        for changed in transitions {
            var r = RemoteSourceRouter(); let routing = InputRoutingSnapshot(producers: [p])
            r.update(routing, configuration: baseline)
            edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
            let work = r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
            var released = 0; r.update(routing, configuration: changed) { _,_,_ in released += 1 }
            #expect(released == 1 && work.validity?.isCurrent == false && p.work.isCurrent)
            r.update(routing, configuration: baseline)
            #expect(r.process(.init(.down, keyCode: 8, modifiers: .control, isRepeat: true), evidence: evidence).decision == .suppress)
            _ = r.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence)
            edge(&r, side: .leftControl, key: 59, flags: [], down: false)
            edge(&r, side: .leftControl, key: 59, flags: .control, down: true)
            #expect(r.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence).decision ==
                    .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        }
    }
}
