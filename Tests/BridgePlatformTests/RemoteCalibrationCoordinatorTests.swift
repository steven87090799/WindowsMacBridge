import Foundation
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor struct RemoteCalibrationCoordinatorTests {
    private func policy(_ context: ApplicationContext = .init(processID: 10, bundleID: "local.WindowsMacBridge", mode: .disabled),
                        paused: Bool = false) -> RuntimePolicySnapshot {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true; input.foreground = context; input.paused = paused
        var coordinator = RuntimePolicyCoordinator(); return coordinator.transition(input)
    }
    private func source(observed: Bool = true) -> RemoteSourceStatus {
        .init(identity: "remoteA", displayName: "Test Remote", processID: 42, session: 9,
              transport: .generic, confidence: .unknown, semantics: .automatic, observedInput: observed, learned: false)
    }
    private func producer() -> RemoteProducer {
        .init(processID: 42, identity: "remoteA", session: 9, revision: 1, transport: .generic, confidence: .unknown)
    }
    @Test func explicitCalibrationSurvivesLocalFocusChangeAndWaitsForConfirmation() throws {
        let inbox = RemoteCalibrationInbox(); let producer = producer()
        let coordinator = RemoteCalibrationCoordinator(inbox: inbox, uptime: { 100 }, birth: { _ in 9 })
        #expect(coordinator.begin(source: source(), policy: policy(), producers: [producer], previous: nil))
        inbox.observe(processID: 43, key: 8, phase: .down, flags: .control, repeatKey: false)
        inbox.observe(processID: 42, key: 0, phase: .down, flags: [], repeatKey: false)
        let destination = policy(.init(processID: 11, bundleID: "com.apple.TextEdit", mode: .macOS))
        coordinator.refresh(policy: destination, producers: [producer])
        #expect(coordinator.status.phase == .waiting)
        inbox.observe(processID: 42, key: 8, phase: .down, flags: .command, repeatKey: false)
        coordinator.refresh(policy: destination, producers: [producer])
        #expect(coordinator.status.phase == .review && coordinator.status.candidate == .alreadyTranslated)
        let preference = try #require(coordinator.proposedPreference(policy: destination, producers: [producer]))
        #expect(preference.learned && preference.semantics == .alreadyTranslated)
        #expect(coordinator.status.phase == .review, "Observation alone never saves settings")
        coordinator.didSave(preference, success: true)
        #expect(coordinator.status.phase == .saved && coordinator.status.canUndo)
        let undo = try #require(coordinator.undoProposal(current: [preference]))
        #expect(undo.previous == nil && undo.identity == source().identity)
    }
    @Test func unobservedSourceWrongSessionAndBlockedPolicyCannotBeArmed() {
        let inbox = RemoteCalibrationInbox(); let producer = producer()
        let coordinator = RemoteCalibrationCoordinator(inbox: inbox, uptime: { 100 }, birth: { _ in 9 })
        #expect(!coordinator.begin(source: source(observed: false), policy: policy(), producers: [producer], previous: nil))
        #expect(!coordinator.begin(source: source(), policy: policy(paused: true), producers: [producer], previous: nil))
        let reused = RemoteCalibrationCoordinator(inbox: inbox, birth: { _ in 10 })
        #expect(!reused.begin(source: source(), policy: policy(), producers: [producer], previous: nil))
    }
    @Test func timeoutCancelDeathAndPolicyChangeNeverProduceASetting() {
        for scenario in 0..<6 {
            var now: Double = 100, birth: UInt64 = 9
            let inbox = RemoteCalibrationInbox(); let producer = producer()
            let coordinator = RemoteCalibrationCoordinator(inbox: inbox, uptime: { now }, birth: { _ in birth })
            #expect(coordinator.begin(source: source(), policy: policy(), producers: [producer], previous: nil))
            inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: false)
            var next = policy()
            switch scenario {
            case 0: now = 160
            case 1: coordinator.cancel()
            case 2: producer.work.invalidate()
            case 3: birth = 10
            case 4: next = policy(paused: true)
            default: next = policy(.init(processID: 12, bundleID: "remote.viewer", mode: .remoteWindows))
            }
            #expect(coordinator.proposedPreference(policy: next, producers: [producer]) == nil)
            #expect(!coordinator.status.isActive)
        }
    }
    @Test func undoPreservesPreviousManualPreferenceAndNeverOverwritesALaterEdit() throws {
        let previous = RemoteSourcePreference(identity: "remoteA", semantics: .macOS, transport: .vnc)
        let inbox = RemoteCalibrationInbox(); let producer = producer()
        let coordinator = RemoteCalibrationCoordinator(inbox: inbox, uptime: { 100 }, birth: { _ in 9 })
        #expect(coordinator.begin(source: source(), policy: policy(), producers: [producer], previous: previous))
        inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: false)
        let preference = try #require(coordinator.proposedPreference(policy: policy(), producers: [producer]))
        coordinator.didSave(preference, success: false)
        #expect(coordinator.status.phase == .review && !coordinator.status.canUndo)
        coordinator.didSave(preference, success: true)
        #expect(coordinator.undoProposal(current: [preference])?.previous == previous)
        #expect(coordinator.undoProposal(current: [previous]) == nil)
        #expect(!coordinator.status.canUndo)
    }
    @Test func revokedWorkAndCancelledRequestDoNotObserveOrdinaryTyping() {
        let inbox = RemoteCalibrationInbox(); let gate = SourceWorkGate()
        let first = inbox.arm(identity: "remoteA", processID: 42, session: 9, validity: gate)
        gate.invalidate()
        #expect(!inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: false))
        let second = inbox.arm(identity: "remoteA", processID: 42, session: 9)
        #expect(second != first)
        #expect(!inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: true))
        inbox.cancel()
        #expect(!inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: false))
        #expect(inbox.take() == nil)
    }
}
