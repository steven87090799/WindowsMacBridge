import Foundation

public struct DiagnosticLogQueueStatus: Sendable {
    public let pendingLines: Int, pendingBytes: Int
    public let dropped: UInt64
}
/// One drain closure, 128 slots/64 KiB, 20 messages/sec and no timer. Never log typed input.
public final class BoundedDiagnosticLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "WindowsMacBridge.bounded-log", qos: .utility)
    private let lock = NSLock()
    private var entries = [String?](repeating: nil, count: 128)
    private var readIndex = 0, writeIndex = 0, count = 0, bytes = 0
    private var scheduled = false, reading = false
    private var dropped: UInt64 = 0
    private var window: Double = 0, windowCount = 0
    private var last = "", lastAt: Double = 0
    private let url: URL
    private let sink: (@Sendable (String) -> Void)?
    public init(url: URL, sink: (@Sendable (String) -> Void)? = nil) { self.url = url; self.sink = sink }
    public func log(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let line = String(decoding: message.utf8.prefix(1024), as: UTF8.self)
        lock.lock()
        if now - window >= 1 { window = now; windowCount = 0 }
        guard windowCount < 20, count < entries.count, bytes + line.utf8.count <= 64 * 1024,
              line != last || now - lastAt >= 1 else { dropped &+= 1; lock.unlock(); return }
        windowCount += 1; last = line; lastAt = now
        entries[writeIndex] = line; writeIndex = (writeIndex + 1) % entries.count
        count += 1; bytes += line.utf8.count
        let start = !scheduled; scheduled = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }
    public func snapshot() -> DiagnosticLogQueueStatus {
        lock.lock(); defer { lock.unlock() }
        return .init(pendingLines: count, pendingBytes: bytes, dropped: dropped)
    }
    private func pop() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard count > 0 else { scheduled = false; return nil }
        let line = entries[readIndex]!
        entries[readIndex] = nil; readIndex = (readIndex + 1) % entries.count
        count -= 1; bytes -= line.utf8.count
        return line
    }
    private func drain() {
        let formatter = ISO8601DateFormatter()
        while let line = pop() {
            if let sink { sink(line); continue }
            autoreleasepool {
                do {
                    let manager = FileManager.default
                    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
                    if let size = (try? manager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue >= 512 * 1024 {
                        let previous = url.appendingPathExtension("1")
                        try? manager.removeItem(at: previous); try manager.moveItem(at: url, to: previous)
                    }
                    let data = Data("[\(formatter.string(from: Date()))] \(line)\n".utf8)
                    if !manager.fileExists(atPath: url.path) {
                        manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                    }
                    let file = try FileHandle(forWritingTo: url)
                    defer { try? file.close() }
                    try file.seekToEnd(); try file.write(contentsOf: data)
                } catch { /* UI status carries operational errors; disk failure never grows this queue. */ }
            }
        }
    }
    /// At most one background tail request. Reads only the final 64 KiB.
    @discardableResult public func readRecent(_ completion: @escaping @Sendable (String) -> Void) -> Bool {
        lock.lock()
        guard !reading else { lock.unlock(); return false }
        reading = true; lock.unlock()
        queue.async { [self] in
            var text = "尚無診斷記錄。"
            if let file = try? FileHandle(forReadingFrom: url) {
                defer { try? file.close() }
                if let size = try? file.seekToEnd() {
                    try? file.seek(toOffset: size > 65536 ? size - 65536 : 0)
                    if let data = try? file.read(upToCount: 65536) {
                        text = String(decoding: data, as: UTF8.self).split(separator: "\n").suffix(150).joined(separator: "\n")
                    }
                }
            }
            lock.lock(); reading = false; lock.unlock()
            completion(text)
        }
        return true
    }
    @discardableResult public func flush() -> Bool {
        let finished = DispatchSemaphore(value: 0)
        queue.async { finished.signal() }
        return finished.wait(timeout: .now() + 1) == .success
    }
}
