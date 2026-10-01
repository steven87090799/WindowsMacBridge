import Foundation
import Testing
@testable import BridgeCore

struct BoundedLoggerTests {
    @Test func slowDiskAndEventStormHaveBoundedPendingBytesAndOneDrain() {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let logger = BoundedDiagnosticLogger(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) { _ in
            entered.signal(); release.wait()
        }
        logger.log("first")
        #expect(entered.wait(timeout: .now() + 2) == .success)
        for i in 0..<100_000 { logger.log("storm \(i)") }
        let status = logger.snapshot()
        #expect(status.pendingLines <= 128 && status.pendingBytes <= 64 * 1024)
        #expect(status.dropped > 99_900)
        for _ in 0..<130 { release.signal() }
        logger.flush()
        #expect(logger.snapshot().pendingLines == 0)
    }
}

struct DeferredSignalMailboxTests {
    @Test func notificationStormSchedulesOnlyOneDrainAndInvalidationDropsOldSignals() {
        let mailbox = DeferredSignalMailbox()
        var schedules = 0
        for n in 0..<100000 { if mailbox.offer(n % 2 == 0 ? 1 : 2) { schedules += 1 } }
        #expect(schedules == 1 && mailbox.take() == 3)
        #expect(mailbox.offer(1))
        mailbox.invalidate()
        #expect(mailbox.take() == 0)
        #expect(mailbox.offer(2) && mailbox.take() == 2)
    }
}

struct BoundedActionInboxTests {
    @Test func stalledActorCannotAccumulateTasksOrUnboundedIPCActions() {
        let inbox = BoundedActionInbox()
        var schedules = 0
        for _ in 0..<100000 { if inbox.offer(.init(action: .finder(.copy), processID: 1, generation: 1)) { schedules += 1 } }
        var count = 0
        while inbox.pop() != nil { count += 1 }
        #expect(schedules == 1 && count == 16)
        #expect(inbox.offer(.init(action: .finder(.copy), processID: 1, generation: 2)))
        #expect(inbox.pop()?.generation == 2 && inbox.pop() == nil)
    }
}
