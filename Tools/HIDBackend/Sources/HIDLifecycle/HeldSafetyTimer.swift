import Foundation

/// Confined to the capture RunLoop. Owns one timer, cancelled at neutral or stop.
public final class HeldSafetyTimer {
    private var timer: Timer?
    public private(set) var deadline: Double?
    public init() {}
    public func cancel() { timer?.invalidate(); timer = nil; deadline = nil }
    public func schedule(after delay: Double?, now: Double = ProcessInfo.processInfo.systemUptime,
                         handler: @escaping () -> Void) {
        guard let delay else { cancel(); return }
        let proposed = now + delay
        // Reuse an earlier timer, but never let a held-only deadline delay a
        // newly outstanding report. Further key edges cannot postpone a check.
        if let timer, timer.isValid, let deadline, deadline <= proposed { return }
        timer?.invalidate()
        deadline = proposed
        let next = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil; self.deadline = nil; handler()
        }
        timer = next
    }
    deinit { timer?.invalidate() }
}
