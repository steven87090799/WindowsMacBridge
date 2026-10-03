import Testing
@testable import InputSourceSupport

@MainActor struct ObserverLifetimeTests {
    @Test func carbonHandlerDoesNotKeepManagerAliveWithoutExplicitStop() {
        weak var retired: HotkeyManager?
        do { let manager = HotkeyManager(); retired = manager }
        #expect(retired == nil)
    }
    @Test func distributedObserverDoesNotSelfRetainAndCanStartStopTwice() {
        weak var retired: GuardController?
        do {
            let controller = GuardController(); retired = controller
            controller.start(); controller.stop(); controller.start()
            // Final deinit must unregister TIS even when the host forgets stop.
        }
        #expect(retired == nil)
    }
}
