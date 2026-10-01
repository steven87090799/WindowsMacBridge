import Foundation

/// Fixed IPC ingress. Only the first accepted entry schedules a drain, regardless of producer rate.
public final class BoundedActionInbox: @unchecked Sendable {
    public struct Entry: Sendable {
        public let action: ShortcutAction
        public let processID: Int32
        public let generation: UInt64
        public init(action: ShortcutAction, processID: Int32, generation: UInt64) {
            self.action = action; self.processID = processID; self.generation = generation
        }
    }
    private let lock = NSLock()
    private var entries = [Entry?](repeating: nil, count: 16)
    private var head = 0, tail = 0, count = 0
    private var scheduled = false
    public init() {}
    public func offer(_ entry: Entry) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        guard count < entries.count else { return false }
        entries[tail] = entry; tail = (tail + 1) % entries.count; count += 1
        guard !scheduled else { return false }
        scheduled = true; return true
    }
    public func pop() -> Entry? {
        lock.lock(); defer { lock.unlock() }
        guard count > 0 else { scheduled = false; return nil }
        let entry = entries[head]; entries[head] = nil
        head = (head + 1) % entries.count; count -= 1; return entry
    }
}
