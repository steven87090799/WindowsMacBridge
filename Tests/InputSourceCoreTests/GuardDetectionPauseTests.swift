import Foundation
import Testing
@testable import InputSourceCore

struct GuardDetectionPauseTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func timedPauseExpiresAtItsAbsoluteDeadline() {
        let pause = GuardDetectionPause(duration: .fifteenMinutes, now: now)
        #expect(pause.until == now.addingTimeInterval(900))
        #expect(pause.isActive(at: now.addingTimeInterval(899)))
        #expect(!pause.isActive(at: now.addingTimeInterval(900)))
    }
    @Test func sleepAndRestartDoNotExtendPause() {
        let original = GuardDetectionPause(duration: .fiveMinutes, now: now)
        let restored = GuardDetectionPause(until: original.until, indefinite: original.indefinite)
        #expect(restored.isActive(at: now.addingTimeInterval(100)))
        #expect(!restored.isActive(at: now.addingTimeInterval(3_600)))
    }
    @Test func indefinitePauseNeedsExplicitResume() {
        let pause = GuardDetectionPause(duration: .untilResumed, now: now)
        #expect(pause.until == nil)
        #expect(pause.isActive(at: now.addingTimeInterval(86_400 * 30)))
        #expect(!GuardDetectionPause().isActive(at: now))
    }
    @Test func replacingPauseUsesOnlyTheNewDeadline() {
        var pause = GuardDetectionPause(duration: .fiveMinutes, now: now)
        pause = GuardDetectionPause(duration: .oneHour, now: now.addingTimeInterval(60))
        #expect(pause.isActive(at: now.addingTimeInterval(300)))
        #expect(pause.until == now.addingTimeInterval(3_660))
    }
    @Test func pauseExpiryRestoresExplicitTargetInsteadOfAdoptingCurrentSource() {
        let pause = GuardDetectionPause(duration: .fiveMinutes, now: now)
        var machine = GuardStateMachine()
        #expect(!pause.isActive(at: now.addingTimeInterval(301)))
        #expect(machine.observeExternalSelection(.abc) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.desired == .vChewing)
        #expect(machine.beginSelectionAttempt() == 1)
    }
}
