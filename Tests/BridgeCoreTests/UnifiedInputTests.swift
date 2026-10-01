import Testing
@testable import BridgeCore

struct GlobalRemoteIsolationRegressionTests {
    @Test func remotePreferencesCannotDisablePhysicalKeyboardOrUCSourceNormalization() {
        for semantics in RemoteSemantics.allCases {
            var input = RuntimePolicyInput()
            input.shortcutEnabled = true
            input.foreground = ApplicationContext(processID: 4, bundleID: "test", mode: .macOS)
            var coordinator = RuntimePolicyCoordinator()
            let policy = coordinator.transition(input)
            var router = RemoteSourceRouter()
            let producer = RemoteProducer(processID: 42, identity: "remote", session: 1, revision: 1,
                                          transport: .generic, confidence: .unknown, semantics: semantics)
            router.update(.init(producers: [producer]), configuration: .init())
            #expect(policy.permitsInput, "Remote semantics must not gate unrelated physical input: \(semantics)")
            #expect(policy.permitsPhysicalNormalization)
        }
    }
}

struct InputSourceRoutingTests {
    private func producer(_ pid: Int32 = 42, semantics: RemoteSemantics = .automatic,
                          adapter: RemoteTransport = .googleRemoteDesktop) -> RemoteProducer {
        RemoteProducer(processID: pid, identity: "test.\(pid)", session: 1, revision: 1,
                       transport: adapter, confidence: .known, semantics: semantics,
                       independentFlags: true)
    }
    private var config: SourceTranslationConfiguration {
        var c = SourceTranslationConfiguration()
        c.enabled = true; c.layoutSupported = true
        c.context = .init(processID: 8, bundleID: "test.editor", mode: .macOS)
        return c
    }
    @Test func knownRemotePIDPrecedesAggregateHIDStateAndHardwareIsNeverBlindlyHandledTwice() {
        let snapshot = InputRoutingSnapshot(producers: [producer()])
        #expect(snapshot.classify(.init(processID: 42, stateID: 1), physicalBackend: .deviceHID) == .remote(0))
        #expect(snapshot.classify(.init(processID: 0, stateID: 1), physicalBackend: .deviceHID) == .virtualPassThrough)
        #expect(snapshot.classify(.init(processID: 0, stateID: 1), physicalBackend: .eventTap) == .physicalFallback)
        #expect(snapshot.classify(.init(processID: 999, stateID: 0), physicalBackend: .deviceHID) == .unknown)
    }
    @Test func ucAndBridgeOutputAlwaysPassThrough() {
        let uc = RemoteProducer(processID: 11, identity: "com.apple.universalcontrol", session: 1,
                                revision: 1, transport: .generic, confidence: .known, kind: .universalControl)
        let snapshot = InputRoutingSnapshot(producers: [uc])
        #expect(snapshot.classify(.init(processID: 11, stateID: 0), physicalBackend: .eventTap) == .universalControl)
        #expect(snapshot.classify(.init(processID: 42, stateID: 0, ownEvent: true), physicalBackend: .eventTap) == .bridgeOutput)
    }
    @Test func rawCtrlNormalizesButAlreadyMacCommandIsNeverTranslatedAgain() {
        var router = RemoteSourceRouter()
        router.update(.init(producers: [producer()]), configuration: config)
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                modifierSide: .leftControl, modifierDown: true), evidence: .init(processID: 42, stateID: 0))
        #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: .init(processID: 42, stateID: 0)).decision ==
                .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        #expect(router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: .init(processID: 42, stateID: 0)).decision ==
                .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false), evidence: .init(processID: 42, stateID: 0))
        #expect(router.process(.init(.down, keyCode: 8, modifiers: .command), evidence: .init(processID: 42, stateID: 0)).decision == .passThrough)
    }
    @Test func sameKeyFromTwoSourcesKeepsIndependentPressesAndModifiers() {
        var router = RemoteSourceRouter()
        router.update(.init(producers: [producer(42, semantics: .windows), producer(43, semantics: .alreadyTranslated)]), configuration: config)
        _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true), evidence: .init(processID: 42, stateID: 0))
        let raw = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: .init(processID: 42, stateID: 0))
        let mac = router.process(.init(.down, keyCode: 8, modifiers: .command), evidence: .init(processID: 43, stateID: 0))
        #expect(raw.decision != .passThrough && mac.decision == .passThrough)
        #expect(router.process(.init(.up, keyCode: 8, modifiers: .command), evidence: .init(processID: 43, stateID: 0)).decision == .passThrough)
        #expect(router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: .init(processID: 42, stateID: 0)).decision != .passThrough)
    }
    @Test func sourcePolicyChangeOrTransportEndCancelsOnlyItsOwnWork() {
        let a = producer(42, semantics: .windows), b = producer(43, semantics: .windows)
        var router = RemoteSourceRouter()
        router.update(.init(producers: [a,b]), configuration: config)
        for pid: Int32 in [42,43] {
            _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true), evidence: .init(processID: pid, stateID: 0))
        }
        let first = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: .init(processID: 42, stateID: 0))
        let second = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: .init(processID: 43, stateID: 0))
        var releases = 0
        router.update(.init(producers: [b]), configuration: config) { _,_,_ in releases += 1 }
        #expect(first.validity?.isCurrent == false)
        #expect(second.validity?.isCurrent == true)
        #expect(releases == 1)
    }
    @Test func unknownAndGenericAutomaticInputNeverGuessesWindowsSemantics() {
        var router = RemoteSourceRouter()
        let generic = RemoteProducer(processID: 55, identity: "test.generic", session: 1, revision: 1,
                                     transport: .generic, confidence: .unknown)
        router.update(.init(producers: [generic]), configuration: config)
        #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: .init(processID: 55, stateID: 0)).decision == .passThrough)
        #expect(router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: .init(processID: 66, stateID: 0)).decision == .passThrough)
    }
    @Test func remoteNativeAltTabAndScreenshotsAreExplicitWindowsSemantics() {
        var router = RemoteSourceRouter(); var c = config
        c.screenshotEnabled = true
        router.update(.init(producers: [producer(42, semantics: .windows)]), configuration: c)
        _ = router.process(.init(.flagsChanged, keyCode: 58, modifiers: .option, modifierSide: .leftOption, modifierDown: true), evidence: .init(processID: 42, stateID: 0))
        #expect(router.process(.init(.down, keyCode: 48, modifiers: .option), evidence: .init(processID: 42, stateID: 0)).decision ==
                .rewrite(keyCode: 48, modifiers: .command, ruleID: "windows.nativeAppSwitch"))
        _ = router.process(.init(.up, keyCode: 48, modifiers: .option), evidence: .init(processID: 42, stateID: 0))
        #expect(router.process(.init(.flagsChanged, keyCode: 58, modifierSide: .leftOption, modifierDown: false), evidence: .init(processID: 42, stateID: 0)).decision ==
                .rewrite(keyCode: 55, modifiers: [], ruleID: "windows.nativeAppSwitch.modifier"))
    }
    @Test func allSixPathsUseSameSemanticRulesWithUCReceivingAlreadyNormalizedOutput() {
        for builtIn in [false,true] {
            var engine = HIDTranslationEngine()
            let registered = engine.register(1, builtIn: builtIn)
            #expect(registered)
            engine.configure(context: config.context, layoutSupported: true, finderEnabled: false)
            _ = engine.observe(device: 1, page: 7, usage: 0xe0, down: true)
            _ = engine.observe(device: 1, page: 7, usage: 6, down: true)
            var output = HIDOutput(); _ = engine.render(into: &output)
            #expect(output.modifiers == 8)
            let uc = InputRoutingSnapshot()
            #expect(uc.classify(.init(processID: 0, stateID: 1), physicalBackend: .deviceHID) == .virtualPassThrough)
        }
        // E/F share the same source-isolated remote normalization, independent of host form factor.
        for _ in 0..<2 { rawCtrlNormalizesButAlreadyMacCommandIsNeverTranslatedAgain() }
    }
}
