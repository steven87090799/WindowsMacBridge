import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor struct ActionDispatcherTests {
    @Test func boundedMailboxAndStopRejectAdditionalActions() {
        // No real PID; queued jobs fail foreground validation without AX, clipboard or output.
        let context = ApplicationContext(processID: .max, bundleID: "test.invalid", mode: .macOS)
        let dispatcher = ShortcutActionDispatcher(marker: 123)
        #expect(dispatcher.update(context: context, enabled: true))
        for _ in 0..<16 { #expect(dispatcher.submit(.system(.openFinder), context: context)) }
        #expect(!dispatcher.submit(.system(.openFinder), context: context))
        dispatcher.cancelPending(disable: true)
        #expect(!dispatcher.submit(.system(.openFinder), context: context))
    }
    @Test func staleContextAndDisabledFinderAreRejectedBeforeQueueing() {
        let context = ApplicationContext(processID: .max, bundleID: "test.invalid", mode: .macOS)
        let dispatcher = ShortcutActionDispatcher(marker: 123)
        #expect(dispatcher.update(context: context, enabled: true, finderEnabled: false))
        #expect(!dispatcher.submit(.finder(.cut), context: context))
        #expect(!dispatcher.submit(.system(.openFinder), context: .init()))
    }
}
