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

@MainActor final class NativeScreenshotCaptureDriver: ScreenshotCaptureDriving {
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        let job = NativeScreenshotJob(prepareArguments: {
            guard !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() else { throw ScreenshotFailure.permissionDenied }
            var args = ["-x", "-t", "png"]
            if kind == .region { args += ["-i", "-s"] }
            if kind == .activeWindow {
                // Explicit capture metadata only; worker pool ends before the process starts.
                guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                      let window = windows.prefix(128).first(where: {
                          ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID &&
                          ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
                          ($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0
                      }), let id = window[kCGWindowNumber as String] as? NSNumber else { throw ScreenshotFailure.processFailure }
                args += ["-l", id.stringValue]
            }
            args.append(url.path); return args
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
            // Parent closes its write endpoint after spawn, so this bounded final
            // read reaches EOF and cannot lose a short child's cancellation message.
            let tail = (try? self.pipe.fileHandleForReading.read(upToCount: 4096)) ?? Data()
            self.diagnostic.append(tail.prefix(max(0, 4096 - self.diagnostic.count)))
            let diagnostic = String(decoding: self.diagnostic, as: UTF8.self).lowercased()
            self.diagnosticLock.unlock()
            self.lock.lock()
            var result = self.failure
            self.lock.unlock()
            if result == nil && finished.terminationStatus != 0 {
                if diagnostic.contains("canceled") || diagnostic.contains("user cancelled") || diagnostic.contains("no selection to capture. cancelling") { result = .userCancelled }
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
        lock.lock(); if failure == nil { failure = .userCancelled }; lock.unlock()
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
