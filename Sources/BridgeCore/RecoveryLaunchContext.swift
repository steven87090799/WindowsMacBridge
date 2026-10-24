import Foundation

/// Only a complete, bounded recovery handoff is acknowledged to the old monitor.
public struct RecoveryLaunchContext: Equatable, Sendable {
    public let attempt: Int
    public let windowMilliseconds: UInt64
    public let token: String?
    public var isRecovery: Bool { token != nil }

    public init(arguments: [String], nowMilliseconds: UInt64) {
        func value(_ flag: String) -> String? {
            let indices = arguments.indices.filter { arguments[$0] == flag }
            guard indices.count == 1, let index = indices.first, index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if let rawAttempt = value("--bridge-recovery-attempt"), let attempt = Int(rawAttempt), (1...3).contains(attempt),
           let rawWindow = value("--bridge-recovery-window"), let window = UInt64(rawWindow), window <= nowMilliseconds,
           // Allow the monitor's 15-second launch deadline at a window boundary.
           // The native policy still resets its attempt window at five minutes.
           nowMilliseconds - window < 315_000,
           let token = value("--bridge-recovery-token"), token.utf8.count == 32,
           token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
            self.attempt = attempt; windowMilliseconds = window; self.token = token
        } else {
            attempt = 0; windowMilliseconds = nowMilliseconds; token = nil
        }
    }
}
