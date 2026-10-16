import Testing
import BridgeCore

struct RemoteRouterUpdateTests {
    @Test func identicalUpdatesPreserveChordAndChangedPolicyReleasesItExactlyOnce() {
        let producer = RemoteProducer(processID: 42, identity: "source", session: 1, revision: 1,
            transport: .generic, confidence: .known, semantics: .windows, independentFlags: true)
        let snapshot = InputRoutingSnapshot(producers: [producer])
        var configuration = SourceTranslationConfiguration()
        configuration.enabled = true; configuration.layoutSupported = true
        configuration.context = .init(processID: 10, bundleID: "local", mode: .macOS)
        var router = RemoteSourceRouter()
        router.update(snapshot, configuration: configuration)
        let evidence = InputOriginEvidence(processID: 42, stateID: -1)
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
            modifierSide: .leftControl, modifierDown: true), evidence: evidence)
        let down = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
        #expect(down.decision == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        var releases: [UInt16] = []
        for _ in 0..<1000 { router.update(snapshot, configuration: configuration) { key, _, _ in releases.append(key) } }
        #expect(releases.isEmpty && down.validity?.isCurrent == true)
        configuration.enabled = false; configuration.generation = 1
        router.update(snapshot, configuration: configuration) { key, _, _ in releases.append(key) }
        #expect(releases == [8] && down.validity?.isCurrent == false)
        router.update(snapshot, configuration: configuration) { key, _, _ in releases.append(key) }
        #expect(releases == [8])
        #expect(router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence).decision == .suppress)
    }
    @Test func sourceRemovalStillRevokesWorkAndDrainsOutputAfterStableUpdates() {
        let producer = RemoteProducer(processID: 42, identity: "source", session: 1, revision: 1,
            transport: .generic, confidence: .known, semantics: .windows, independentFlags: true)
        let snapshot = InputRoutingSnapshot(producers: [producer])
        var configuration = SourceTranslationConfiguration(); configuration.enabled = true; configuration.layoutSupported = true
        configuration.context = .init(processID: 10, bundleID: "local", mode: .macOS)
        var router = RemoteSourceRouter(); router.update(snapshot, configuration: configuration)
        let evidence = InputOriginEvidence(processID: 42, stateID: -1)
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true), evidence: evidence)
        _ = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
        router.update(snapshot, configuration: configuration)
        var releases = 0
        router.update(.init(), configuration: configuration) { _, _, _ in releases += 1 }
        #expect(releases == 1 && !producer.work.isCurrent)
        #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence).decision == .passThrough)
    }
}
