import Testing
@testable import BridgeCore

struct RecoveryLaunchContextTests {
    let token = String(repeating: "a1", count: 16)
    func arguments(attempt: String = "1", window: String = "1000", token: String? = nil) -> [String] {
        ["App", "--bridge-recovery-attempt", attempt, "--bridge-recovery-window", window,
         "--bridge-recovery-token", token ?? self.token]
    }
    @Test func manualLaunchStartsANewRecoveryWindow() {
        let state = RecoveryLaunchContext(arguments: ["App"], nowMilliseconds: 1234)
        #expect(state.attempt == 0 && state.windowMilliseconds == 1234 && !state.isRecovery)
    }
    @Test func completeBoundedHandoffPreservesAttemptAndAcknowledgment() {
        for attempt in 1...3 {
            let state = RecoveryLaunchContext(arguments: arguments(attempt: String(attempt)), nowMilliseconds: 2000)
            #expect(state.attempt == attempt && state.windowMilliseconds == 1000 && state.token == token)
        }
    }
    @Test func malformedOrMissingFieldsCannotAcknowledgeARecovery() {
        for args in [arguments(attempt: "0"), arguments(attempt: "4"), arguments(attempt: "-1"),
                     arguments(attempt: "999999999999999999999999999"), arguments(window: "invalid"),
                     ["--bridge-recovery-attempt", "1"], arguments() + ["--bridge-recovery-attempt", "2"]] {
            #expect(!RecoveryLaunchContext(arguments: args, nowMilliseconds: 2000).isRecovery)
        }
    }
    @Test func staleAndFutureWindowsStartFreshInsteadOfExtendingACrashLoop() {
        for now: UInt64 in [999, 316000, 900000] {
            let state = RecoveryLaunchContext(arguments: arguments(), nowMilliseconds: now)
            #expect(!state.isRecovery && state.windowMilliseconds == now && state.attempt == 0)
        }
        #expect(RecoveryLaunchContext(arguments: arguments(), nowMilliseconds: 300999).isRecovery)
        #expect(RecoveryLaunchContext(arguments: arguments(), nowMilliseconds: 301001).isRecovery)
    }
    @Test func onlyFixedLengthHexTokensCanNameAcknowledgmentFiles() {
        for value in ["", "../outside", String(repeating: "x", count: 32), String(repeating: "a", count: 33)] {
            #expect(!RecoveryLaunchContext(arguments: arguments(token: value), nowMilliseconds: 2000).isRecovery)
        }
    }
}
