import Testing
import BridgeCore
@testable import BridgePlatform

struct EngineWakePolicyTests {
    @Test func counterOnlyChangesDoNotWakeTheHostOnEveryKeystroke() {
        var previous = EngineStatus(); previous.tapActive = true; previous.awaitingNeutral = false
        var next = previous; next.processed = 10; next.translated = 3; next.maxMicroseconds = 12
        #expect(!InputEngine.requiresHostWake(previous: previous, next: next, everyChange: false))
        // Live diagnostics or a pending Fn/Ctrl neutral check still observe every edge.
        #expect(InputEngine.requiresHostWake(previous: previous, next: next, everyChange: true))
        #expect(!InputEngine.requiresHostWake(previous: previous, next: previous, everyChange: true))
    }
    @Test func everyMaterialStatusChangeStillWakesTheHost() {
        var previous = EngineStatus(); previous.tapActive = true; previous.awaitingNeutral = false
        previous.processed = 1
        let mutations: [(inout EngineStatus) -> Void] = [
            { $0.accessibility.toggle() }, { $0.listenAccess.toggle() }, { $0.postAccess.toggle() },
            { $0.secureInput.toggle() }, { $0.tapActive.toggle() }, { $0.awaitingNeutral.toggle() },
            { $0.fault = "fault" }, { $0.emergencyPaused.toggle() }, { $0.manualPassThrough.toggle() },
            { $0.backendIssue = "issue" }, { $0.actionStatus = "action" },
            { $0.diagnostics = [DiagnosticRecord(id: 1, rule: "rule", application: "app", microseconds: 1)] }
        ]
        for mutation in mutations {
            var next = previous; next.processed = 2
            mutation(&next)
            #expect(InputEngine.requiresHostWake(previous: previous, next: next, everyChange: false))
        }
    }
    @Test func completedCalibrationReportsItselfSoTheHostIsWokenForIt() {
        let inbox = RemoteCalibrationInbox()
        #expect(!inbox.observe(processID: 7, key: 8, phase: .down, flags: .control, repeatKey: false))
        inbox.arm(identity: "source", processID: 7, session: 1)
        #expect(!inbox.observe(processID: 8, key: 8, phase: .down, flags: .control, repeatKey: false))
        #expect(!inbox.observe(processID: 7, key: 9, phase: .down, flags: .control, repeatKey: false))
        #expect(!inbox.observe(processID: 7, key: 8, phase: .down, flags: .control, repeatKey: true))
        #expect(inbox.observe(processID: 7, key: 8, phase: .down, flags: .control, repeatKey: false))
        #expect(inbox.take()?.semantics == .windows)
        #expect(!inbox.observe(processID: 7, key: 8, phase: .down, flags: .control, repeatKey: false))
    }
}
