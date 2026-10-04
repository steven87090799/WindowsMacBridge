import Testing
import HIDLifecycle

struct HeldSafetyTimerTests {
    @Test func outstandingOutputAdvancesAnAlreadyArmedHeldOnlyDeadline() {
        let timer = HeldSafetyTimer(); defer { timer.cancel() }
        timer.schedule(after: HeldSafetyPolicy.heldDeadline, now: 100) {}
        #expect(timer.deadline == 101)
        timer.schedule(after: HeldSafetyPolicy.outstandingDeadline, now: 100.1) {}
        #expect(timer.deadline == 100.1 + HeldSafetyPolicy.outstandingDeadline, "outstanding output must shorten the existing deadline")
    }
    @Test func moreKeyEdgesNeverPostponeAnEarlierCheck() {
        let timer = HeldSafetyTimer(); defer { timer.cancel() }
        timer.schedule(after: HeldSafetyPolicy.outstandingDeadline, now: 100) {}
        for edge in 1...10 { timer.schedule(after: 1, now: 100 + Double(edge) / 100) {} }
        #expect(timer.deadline == 100.6)
    }
    @Test func neutralAndStopRemoveTheDeadline() {
        let timer = HeldSafetyTimer()
        timer.schedule(after: 0.6, now: 100) {}
        timer.schedule(after: nil, now: 100.1) {}
        #expect(timer.deadline == nil)
        timer.schedule(after: 1, now: 101) {}
        #expect(timer.deadline == 102)
        timer.cancel()
        #expect(timer.deadline == nil)
    }
}
