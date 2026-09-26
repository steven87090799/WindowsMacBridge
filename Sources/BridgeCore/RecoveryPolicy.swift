public struct RecoveryPolicy: Sendable {
    private var windowStart: Double = 0
    private var attempts = 0
    public init() {}
    /// Third failure within sixty seconds trips the circuit. Time is injected for deterministic tests.
    public mutating func mayRetry(at time: Double) -> Bool {
        if time - windowStart >= 60 || time < windowStart { windowStart = time; attempts = 0 }
        attempts += 1
        return attempts < 3
    }
    public mutating func reset() { attempts = 0; windowStart = 0 }
}
