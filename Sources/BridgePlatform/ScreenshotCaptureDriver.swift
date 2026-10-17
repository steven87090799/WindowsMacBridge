import Foundation
import CoreGraphics
import Carbon
import Darwin
import BridgeCore

public protocol ScreenshotCaptureJob: AnyObject, Sendable {
    func cancel(_ reason: ScreenshotFailure)
    func noteUserCancellation()
}
@MainActor public protocol ScreenshotCaptureDriving: AnyObject {
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob
}

/// System presentation owns its destination, floating thumbnail and editor.
/// A successful process exit does not imply that the user has saved a file.
@MainActor protocol SystemScreenshotCaptureDriving: ScreenshotCaptureDriving {
    func launchSystemUI(kind: ScreenshotKind, processID: Int32,
                        completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob
}

@MainActor final class NativeScreenshotCaptureDriver: SystemScreenshotCaptureDriving {
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        try launch(destination: url, kind: kind, processID: processID, completion: completion)
    }

    func launchSystemUI(kind: ScreenshotKind, processID: Int32,
                        completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        try launch(destination: nil, kind: kind, processID: processID, completion: completion)
    }

    /// `-u` delegates storage and post-capture presentation to macOS. It ignores
    /// command-line file paths; only private OCR captures request a PNG path.
    nonisolated static func arguments(kind: ScreenshotKind, destination: URL?, windowID: NSNumber? = nil) throws -> [String] {
        var args = destination == nil ? ["-u", "-p"] : ["-x", "-t", "png"]
        if kind == .region { args += destination == nil ? ["-i"] : ["-i", "-s"] }
        if kind == .activeWindow {
            guard let windowID else { throw ScreenshotFailure.processFailure }
            args += ["-l", windowID.stringValue]
        }
        if let destination { args.append(destination.path) }
        return args
    }

    private func launch(destination: URL?, kind: ScreenshotKind, processID: Int32,
                        completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        let job = NativeScreenshotJob(prepareArguments: {
            guard !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() else { throw ScreenshotFailure.permissionDenied }
            var windowID: NSNumber?
            if kind == .activeWindow {
                // Explicit capture metadata only; worker pool ends before the process starts.
                guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                      let window = windows.prefix(128).first(where: {
                          ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID &&
                          ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
                          ($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0
                      }), let id = window[kCGWindowNumber as String] as? NSNumber else { throw ScreenshotFailure.processFailure }
                windowID = id
            }
            return try Self.arguments(kind: kind, destination: destination, windowID: windowID)
        }, completion: completion)
        job.start(); return job
    }
}

/// The manager's single-flight slot bounds this serial queue to one capture job.
final class NativeScreenshotJob: ScreenshotCaptureJob, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "WindowsMacBridge.screenshot-launch", qos: .userInitiated)
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private let diagnosticLock = NSLock()
    private var failure: ScreenshotFailure?
    /// Esc during region selection only explains a non-zero exit; it must not
    /// discard a capture that screencapture completed successfully.
    private var userCancellationNoted = false
    private var diagnostic = Data()
    private var terminationSent = false, startRequested = false
    private let prepareArguments: @Sendable () throws -> [String]
    private let completion: @Sendable (Int32, ScreenshotFailure?) -> Void
    init(executable: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"),
         prepareArguments: @escaping @Sendable () throws -> [String],
         completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) {
        self.prepareArguments = prepareArguments; self.completion = completion
        process.executableURL = executable; process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { handle.readabilityHandler = nil; return }
            self.diagnosticLock.lock()
            let bytes = (try? handle.read(upToCount: 4096)) ?? Data()
            if bytes.isEmpty { handle.readabilityHandler = nil; self.diagnosticLock.unlock(); return }
            self.diagnostic.append(bytes.prefix(max(0, 4096 - self.diagnostic.count)))
            self.diagnosticLock.unlock()
        }
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.pipe.fileHandleForReading.readabilityHandler = nil
            self.diagnosticLock.lock()
            // The child has exited, so its output is already buffered. Read it
            // without blocking: an inherited write end must never stall completion
            // and hold the single capture slot until relaunch.
            let descriptor = self.pipe.fileHandleForReading.fileDescriptor
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }
            let tail = (try? self.pipe.fileHandleForReading.read(upToCount: 4096)) ?? Data()
            self.diagnostic.append(tail.prefix(max(0, 4096 - self.diagnostic.count)))
            let diagnostic = String(decoding: self.diagnostic, as: UTF8.self).lowercased()
            self.diagnosticLock.unlock()
            self.lock.lock()
            var result = self.failure
            let escaped = self.userCancellationNoted
            self.lock.unlock()
            if result == nil && finished.terminationStatus != 0 {
                if escaped || diagnostic.contains("canceled") || diagnostic.contains("user cancelled") || diagnostic.contains("no selection to capture. cancelling") { result = .userCancelled }
                else if diagnostic.contains("denied") || diagnostic.contains("not permitted") || diagnostic.contains("permission") { result = .permissionDenied }
                else if diagnostic.contains("no space") || diagnostic.contains("write") { result = .diskFailure }
                else { result = .processFailure }
            }
            completion(finished.terminationStatus, result)
        }
    }
    private var cancellation: ScreenshotFailure? { lock.lock(); defer { lock.unlock() }; return failure }
    func start() {
        lock.lock()
        guard !startRequested else { lock.unlock(); return }
        startRequested = true; lock.unlock()
        Self.queue.async { [self] in
            autoreleasepool {
                if let reason = cancellation { completion(1, reason); return }
                do {
                    process.arguments = try prepareArguments()
                    if let reason = cancellation { completion(1, reason); return }
                    try process.run()
                    try? pipe.fileHandleForWriting.close()
                    if cancellation != nil { terminateIfRunning() }
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    try? pipe.fileHandleForWriting.close()
                    completion(1, cancellation ?? (error as? ScreenshotFailure) ?? .processFailure)
                }
            }
        }
    }
    func noteUserCancellation() {
        lock.lock(); userCancellationNoted = true; lock.unlock()
    }
    func cancel(_ reason: ScreenshotFailure) {
        lock.lock(); if failure == nil { failure = reason }; lock.unlock()
        terminateIfRunning()
    }
    private func terminateIfRunning() {
        guard process.isRunning else { return }
        lock.lock()
        guard !terminationSent else { lock.unlock(); return }
        terminationSent = true; lock.unlock()
        process.terminate()
        // One escalation for this still-running owned child; never a new capture job.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.process.isRunning else { return }
            _ = kill(self.process.processIdentifier, SIGKILL)
        }
    }
}
