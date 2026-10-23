import Foundation

/// Input-thread confined. Allocate only after the first record in an explicitly
/// enabled session; expiry releases both records and ring storage.
struct InputDiagnostics {
    static let limit = 128
    private var records: [DiagnosticRecord?] = []
    private var next = 0
    private var sequence: UInt64 = 0
    private var requested = false
    private(set) var count = 0
    private(set) var deadline: TimeInterval?
    private(set) var revision: UInt64 = 0
    var allocatedSlots: Int { records.count }

    mutating func configure(enabled: Bool, now: TimeInterval) {
        guard enabled != requested else { return }
        requested = enabled
        clear()
        deadline = enabled ? now + 300 : nil
    }

    func isActive(at now: TimeInterval) -> Bool {
        requested && deadline.map { now < $0 } == true
    }

    mutating func expire(at now: TimeInterval) {
        if let deadline, now >= deadline { clear() }
    }

    private mutating func clear() {
        if count > 0 { revision &+= 1 }
        records = []; count = 0; next = 0; deadline = nil
    }

    mutating func append(rule: String, application: String, microseconds: Double,
                         detail: String? = nil, now: TimeInterval) {
        guard isActive(at: now) else { return }
        if records.isEmpty { records = Array(repeating: nil, count: Self.limit) }
        sequence &+= 1
        records[next] = DiagnosticRecord(id: sequence, rule: Self.bounded(rule, bytes: 256),
            application: Self.bounded(application, bytes: 256), microseconds: microseconds,
            detail: detail.map { Self.bounded($0, bytes: 1024) })
        next = (next + 1) % Self.limit
        count = min(count + 1, Self.limit)
        revision &+= 1
    }

    /// The ring already encodes chronology. No intermediate compactMap or sort.
    func snapshot() -> [DiagnosticRecord] {
        var result: [DiagnosticRecord] = []
        result.reserveCapacity(count)
        for offset in 0..<count {
            if let record = records[(next - 1 - offset + Self.limit) % Self.limit] {
                result.append(record)
            }
        }
        return result
    }

    private static func bounded(_ value: String, bytes limit: Int) -> String {
        guard value.utf8.count > limit else { return value }
        var bytes = Array(value.utf8.prefix(limit))
        // A UTF-8 scalar spans at most four bytes. Trim only an incomplete tail.
        for _ in 0..<4 {
            if let text = String(bytes: bytes, encoding: .utf8) { return text }
            bytes.removeLast()
        }
        return ""
    }
}
