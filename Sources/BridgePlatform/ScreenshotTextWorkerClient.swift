import Foundation
import Darwin
import BridgeCore

public protocol ScreenshotTextRecognizing: Sendable {
    func recognize(png: Data) async -> Result<String, ScreenshotFailure>
}

public struct IsolatedScreenshotTextRecognizer: ScreenshotTextRecognizing {
    private let executable: URL?
    private let timeout: TimeInterval
    public init(executable: URL? = nil, timeout: TimeInterval = 30) {
        self.executable = executable ?? Self.bundledExecutable()
        self.timeout = timeout.isFinite && timeout > 0 ? min(60, timeout) : 30
    }
    /// Pure path resolution: no framework load, preheat, process or polling.
    public static func bundledExecutable(bundle: Bundle = .main) -> URL? {
        if bundle.bundleURL.pathExtension == "app" {
            return bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(ScreenshotTextBudget.workerExecutableName)")
        }
        return bundle.executableURL?.deletingLastPathComponent().appendingPathComponent(ScreenshotTextBudget.workerExecutableName)
    }
    public func recognize(png: Data) async -> Result<String, ScreenshotFailure> {
        guard let executable, !png.isEmpty, png.count <= ImageMemoryBudget.maximumFileBytes else { return .failure(.decodeFailure) }
        let job = ScreenshotTextProcess(executable: executable, timeout: timeout)
        return await withTaskCancellationHandler {
            if Task.isCancelled { job.cancel(.policyCancelled) }
            return await withCheckedContinuation { continuation in
                job.start(png: png) { continuation.resume(returning: $0) }
            }
        } onCancel: { job.cancel(.policyCancelled) }
    }
}

/// One owned child, bounded reply and a private input snapshot. The manager's
/// capture slot remains occupied until termination and cleanup are confirmed.
private final class ScreenshotTextProcess: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "WindowsMacBridge.text-worker", qos: .userInitiated)
    private let process = Process(), output = Pipe()
    private let lock = NSLock(), readLock = NSLock()
    private let timeout: TimeInterval
    private var reply = Data()
    private var failure: ScreenshotFailure?
    private var completion: (@Sendable (Result<String, ScreenshotFailure>) -> Void)?
    private var timer: DispatchSourceTimer?
    private var started = false, completed = false, terminationSent = false

    init(executable: URL, timeout: TimeInterval) {
        self.timeout = timeout; process.executableURL = executable
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
    }
    private var cancellation: ScreenshotFailure? { lock.lock(); defer { lock.unlock() }; return failure }
    func start(png: Data, completion: @escaping @Sendable (Result<String, ScreenshotFailure>) -> Void) {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true; self.completion = completion; lock.unlock()
        Self.queue.async { [self] in
            autoreleasepool {
                if let cancellation { finish(.failure(cancellation)); return }
                do {
                    var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("WindowsMacBridge-OCR.XXXXXX").path.utf8CString)
                    let snapshotFD = mkstemp(&template)
                    guard snapshotFD >= 0 else { throw CocoaError(.fileWriteUnknown) }
                    let snapshot = FileHandle(fileDescriptor: snapshotFD, closeOnDealloc: true)
                    defer { try? snapshot.close() }
                    // Remove the name BEFORE writing pixels. Even a crash cannot
                    // leave a named OCR image; the kernel reclaims it at fd close.
                    guard template.withUnsafeBufferPointer({ unlink($0.baseAddress!) }) == 0,
                          fcntl(snapshotFD, F_SETFD, FD_CLOEXEC) >= 0 else { throw CocoaError(.fileWriteUnknown) }
                    try snapshot.write(contentsOf: png)
                    try snapshot.seek(toOffset: 0)
                    if let cancellation { finish(.failure(cancellation)); return }
                    process.standardInput = snapshot
                    process.arguments = [ScreenshotTextBudget.workerArgument]
                    let fd = output.fileHandleForReading.fileDescriptor
                    let flags = fcntl(fd, F_GETFL)
                    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { throw CocoaError(.fileReadUnknown) }
                    output.fileHandleForReading.readabilityHandler = { [weak self] _ in self?.readOutput() }
                    process.terminationHandler = { [self] child in
                        output.fileHandleForReading.readabilityHandler = nil
                        readOutput()
                        readLock.lock(); let data = reply; readLock.unlock()
                        let result = cancellation.map { Result<String, ScreenshotFailure>.failure($0) } ??
                            ((try? JSONDecoder().decode(ScreenshotTextReply.self, from: data))?.result(exitCode: child.terminationStatus) ?? .failure(.recognitionFailure))
                        finish(result)
                    }
                    try process.run()
                    try? output.fileHandleForWriting.close()
                    lock.lock()
                    if !completed {
                        let deadline = DispatchSource.makeTimerSource(queue: Self.queue)
                        deadline.schedule(deadline: .now() + timeout)
                        deadline.setEventHandler { [weak self] in self?.cancel(.timedOut) }
                        timer = deadline; deadline.resume()
                    }
                    lock.unlock()
                    if cancellation != nil { terminate() }
                } catch { finish(.failure(cancellation ?? .processFailure)) }
            }
        }
    }

    private func readOutput() {
        readLock.lock()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var overflow = false, endOfFile = false
        // Also used after child termination. O_NONBLOCK avoids inherited pipe
        // writers keeping the capture slot alive after our worker is gone.
        while true {
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &buffer, 4096)
            if count == 0 { endOfFile = true }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            let remaining = ScreenshotTextBudget.maximumReplyBytes - reply.count
            reply.append(contentsOf: buffer.prefix(min(count, remaining)))
            if count > remaining { overflow = true; break }
        }
        readLock.unlock()
        if endOfFile { output.fileHandleForReading.readabilityHandler = nil }
        if overflow { cancel(.recognitionFailure) }
    }
    func cancel(_ reason: ScreenshotFailure) {
        lock.lock(); if failure == nil { failure = reason }; lock.unlock()
        terminate()
    }
    private func terminate() {
        guard process.isRunning else { return }
        lock.lock()
        guard !terminationSent else { lock.unlock(); return }
        terminationSent = true; lock.unlock()
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.process.isRunning else { return }
            _ = kill(self.process.processIdentifier, SIGKILL)
        }
    }
    private func finish(_ result: Result<String, ScreenshotFailure>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true; let callback = completion; completion = nil
        timer?.cancel(); timer = nil; lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? output.fileHandleForWriting.close()
        callback?(result)
    }
}
