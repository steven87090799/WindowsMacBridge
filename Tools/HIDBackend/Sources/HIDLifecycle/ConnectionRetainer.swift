import Foundation

/// Owns accepted IPC peers until invalidation, including read-only permission
/// probes that never acquire capture. Delegate and invalidation queues may differ.
public final class ConnectionRetainer<Connection: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var peers: [ObjectIdentifier: Connection] = [:]
    public init(limit: Int = 4) { self.limit = max(1, limit) }
    public var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return peers.isEmpty }
    public func insert(_ connection: Connection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let id = ObjectIdentifier(connection)
        guard peers[id] != nil || peers.count < limit else { return false }
        peers[id] = connection
        return true
    }
    public func remove(_ connection: Connection) {
        lock.lock()
        let removed = peers.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
        // Never destroy a connection while holding the registry lock.
        withExtendedLifetime(removed) {}
    }
}
