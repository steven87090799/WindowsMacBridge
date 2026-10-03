import Foundation
import Testing
import BridgeCore
@testable import BridgePlatform

private final class NativeJobProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var mainThread = true
    private var result: ScreenshotFailure?
    private var finished = false
    let release = DispatchSemaphore(value: 0)
    func prepare() -> [String] {
        lock.lock(); entered = true; mainThread = Thread.isMainThread; lock.unlock()
        release.wait()
        return []
    }
    func complete(_ failure: ScreenshotFailure?) { lock.lock(); result = failure; finished = true; lock.unlock() }
    var state: (Bool, Bool, Bool, ScreenshotFailure?) {
        lock.lock(); defer { lock.unlock() }; return (entered, mainThread, finished, result)
    }
}
@MainActor struct NativeScreenshotJobTests {
    @Test func nativeChildDiagnosticsDistinguishCancelPermissionDiskAndProcessFailures() async throws {
        for (message, expected): (String, ScreenshotFailure) in [
            ("No selection to capture. Cancelling", .userCancelled),
            ("permission denied", .permissionDenied),
            ("No space left to write", .diskFailure),
            ("capture process failed", .processFailure)
        ] {
            let probe = NativeJobProbe()
            let job = NativeScreenshotJob(executable: URL(fileURLWithPath: "/bin/sh"),
                prepareArguments: { ["-c", "printf '%s\\n' '\(message)' >&2; exit 1"] },
                completion: { _, failure in probe.complete(failure) })
            job.start()
            for _ in 0..<100 where !probe.state.2 { try await Task.sleep(for: .milliseconds(2)) }
            #expect(probe.state.2 && probe.state.3 == expected)
        }
    }
    @Test func escapeNoteOnlyClassifiesFailedExitsAndNeverDiscardsACapture() async throws {
        for (status, expected): (Int, ScreenshotFailure?) in [(0, nil), (1, .userCancelled)] {
            let probe = NativeJobProbe()
            let job = NativeScreenshotJob(executable: URL(fileURLWithPath: "/bin/sh"),
                prepareArguments: { ["-c", "sleep 0.2; exit \(status)"] },
                completion: { _, failure in probe.complete(failure) })
            job.start()
            job.noteUserCancellation()
            for _ in 0..<200 where !probe.state.2 { try await Task.sleep(for: .milliseconds(5)) }
            #expect(probe.state.2 && probe.state.3 == expected)
        }
    }
    @Test func inheritedDiagnosticPipeCannotStallCompletionAndTheCaptureSlot() async throws {
        // A descendant keeps the stderr write end open after the capture process exits.
        // Completion must arrive while it still holds the pipe; no wall-clock bound,
        // so a stalled CI runner cannot turn this into a timing assertion.
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-pipe-holder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let probe = NativeJobProbe()
        let job = NativeScreenshotJob(executable: URL(fileURLWithPath: "/bin/sh"),
            prepareArguments: { ["-c", "(sleep 60) >&2 & echo $! > '\(pidFile.path)'; exit 0"] },
            completion: { _, failure in probe.complete(failure) })
        job.start()
        for _ in 0..<2000 where !probe.state.2 { try await Task.sleep(for: .milliseconds(10)) }
        let holder = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(probe.state.2 && probe.state.3 == nil)
        #expect(holder.map { kill($0, 0) == 0 } == true, "completion must not wait for the pipe holder to exit")
        if let holder { kill(holder, SIGKILL) }
    }
    @Test func slowPreparationRunsOutsideMainActorAndCancellationPreventsProcessLaunch() async throws {
        let probe = NativeJobProbe()
        let job = NativeScreenshotJob(executable: URL(fileURLWithPath: "/usr/bin/true"), prepareArguments: { probe.prepare() }, completion: { _, failure in probe.complete(failure) })
        job.start()
        for _ in 0..<100 where !probe.state.0 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(probe.state.0 && !probe.state.1)
        job.cancel(.policyCancelled); probe.release.signal()
        for _ in 0..<100 where !probe.state.2 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(probe.state.2 && probe.state.3 == .policyCancelled)
    }
}
