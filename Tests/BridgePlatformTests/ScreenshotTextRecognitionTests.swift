import Foundation
import CoreGraphics
import CoreText
import Darwin
import Testing
import BridgeCore
@testable import BridgePlatform

private struct TextWorkerFixture {
    let directory: URL
    let executable: URL
    init(_ body: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OCR Worker Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        executable = directory.appendingPathComponent("worker")
        try Data(("#!/usr/bin/python3\n" + body).utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

struct ScreenshotTextRecognitionTests {
    @Test func unlinkedRegularDescriptorUsesTheSameBoundedReader() throws {
        let fixture = try TextWorkerFixture("print('{}')"); defer { fixture.remove() }
        let path = fixture.directory.appendingPathComponent("snapshot.bin")
        let bytes = Data("immutable snapshot".utf8)
        try bytes.write(to: path)
        let descriptor = open(path.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        try FileManager.default.removeItem(at: path)
        #expect(BoundedImageFile.read(descriptor: descriptor) == .success(bytes))
        // A caller cannot widen the global budget or trigger an Int overflow.
        #expect(ftruncate(descriptor, off_t(ImageMemoryBudget.maximumFileBytes + 1)) == 0)
        #expect(BoundedImageFile.read(descriptor: descriptor, limit: .max) == .failure(.diskFailure))
        #expect(BoundedImageFile.read(descriptor: descriptor, limit: 0) == .failure(.diskFailure))
    }
    @Test func textLimitsCountUTF8BytesAndNeverSilentlyTruncate() {
        let exact = String(repeating: "a", count: ScreenshotTextBudget.maximumUTF8Bytes)
        #expect(ScreenshotTextBudget.combine([exact]) == .success(exact))
        #expect(ScreenshotTextBudget.combine([exact + "a"]) == .failure(.textTooLarge))
        #expect(ScreenshotTextBudget.combine([String(repeating: "字", count: 22_000)]) == .failure(.textTooLarge))
        #expect(ScreenshotTextBudget.combine(Array(repeating: "line", count: 1001)) == .failure(.textTooLarge))
        #expect(ScreenshotTextBudget.combine(["  ","\n"]) == .failure(.textNotFound))
        #expect(ScreenshotTextBudget.combine([" first "," second "]) == .success("first\nsecond"))
    }
    @Test func workerReceivesOnlyAnUnlinkedPrivateSnapshotAndReturnsText() async throws {
        let fixture = try TextWorkerFixture("""
import os, stat, json, sys
info = os.fstat(0)
assert stat.S_ISREG(info.st_mode)
assert info.st_nlink == 0
assert stat.S_IMODE(info.st_mode) == 0o600
assert os.read(0, 100) == b'private fixture'
assert len(sys.argv) == 2 and sys.argv[1] == '--recognize-screenshot-text'
print(json.dumps({'text':'Local text 123'}))
""")
        defer { fixture.remove() }
        let result = await IsolatedScreenshotTextRecognizer(executable: fixture.executable).recognize(png: Data("private fixture".utf8))
        #expect(result == .success("Local text 123"))
    }
    @Test func malformedOversizedAndFailedRepliesNeverBecomeClipboardText() async throws {
        for body in ["print('not json')", "import json; print(json.dumps({'text':'x' * 65537}))",
                     "import sys; sys.stdout.write('x' * 500000)",
                     "import json, sys; print(json.dumps({'text':'rejected'})); sys.exit(2)"] {
            let fixture = try TextWorkerFixture(body); defer { fixture.remove() }
            let result = await IsolatedScreenshotTextRecognizer(executable: fixture.executable).recognize(png: Data([1]))
            if case .success = result { Issue.record("Invalid worker reply accepted") }
        }
    }
    @Test func workerTimeoutStopsItsOwnedProcess() async throws {
        let fixture = try TextWorkerFixture("import time; time.sleep(30)")
        defer { fixture.remove() }
        let result = await IsolatedScreenshotTextRecognizer(executable: fixture.executable, timeout: 0.1).recognize(png: Data([1]))
        #expect(result == .failure(.timedOut))
    }
    @Test func cancellationStopsEvenAWorkerIgnoringTerminate() async throws {
        let fixture = try TextWorkerFixture("""
import os, signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(__file__ + '.pid', 'w') as output: output.write(str(os.getpid()))
time.sleep(30)
""")
        defer { fixture.remove() }
        let recognizer = IsolatedScreenshotTextRecognizer(executable: fixture.executable)
        let task = Task { await recognizer.recognize(png: Data([1])) }
        defer { task.cancel() }
        let marker = URL(fileURLWithPath: fixture.executable.path + ".pid")
        for _ in 0..<500 where !FileManager.default.fileExists(atPath: marker.path) { try await Task.sleep(for: .milliseconds(10)) }
        let pid = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
        task.cancel()
        #expect(await task.value == .failure(.policyCancelled))
        #expect(kill(pid, 0) != 0 && errno == ESRCH)
    }
    @Test func inheritedStdoutDoesNotHoldTheCaptureSlotAfterWorkerExit() async throws {
        let fixture = try TextWorkerFixture("""
import json, os, time
pid = os.fork()
if pid == 0:
    time.sleep(4)
    os._exit(0)
with open(__file__ + '.child', 'w') as output: output.write(str(pid))
print(json.dumps({'text':'completed'}), flush=True)
""")
        defer { fixture.remove() }
        let start = ProcessInfo.processInfo.systemUptime
        let result = await IsolatedScreenshotTextRecognizer(executable: fixture.executable).recognize(png: Data([1]))
        let marker = URL(fileURLWithPath: fixture.executable.path + ".child")
        if let text = try? String(contentsOf: marker, encoding: .utf8), let child = Int32(text) { _ = kill(child, SIGTERM) }
        #expect(result == .success("completed"))
        #expect(ProcessInfo.processInfo.systemUptime - start < 3)
    }

}
