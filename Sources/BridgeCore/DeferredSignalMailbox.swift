import Foundation

/// At most one drain closure and a fixed bit mask, even during a notification storm.
/// Producers never block. Invalidation discards stale signals without adding another closure.
public final class DeferredSignalMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var bits: UInt32 = 0
    private var scheduled = false
    public init() {}
    public func offer(_ signal: UInt32) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        bits |= signal
        guard !scheduled else { return false }
        scheduled = true
        return true
    }
    public func take() -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        let value = bits; bits = 0; scheduled = false
        return value
    }
    public func invalidate() { lock.lock(); bits = 0; lock.unlock() }
}
