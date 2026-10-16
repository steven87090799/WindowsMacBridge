import AppKit
import Testing
import BridgeCore
import ImageIO
@testable import BridgePlatform

private final class CaptureJobFixture: ScreenshotCaptureJob, @unchecked Sendable {
    var cancellations: [ScreenshotFailure] = []
    func cancel(_ reason: ScreenshotFailure) { cancellations.append(reason) }
    func noteUserCancellation() { cancellations.append(.userCancelled) }
}
@MainActor private final class CaptureDriverFixture: ScreenshotCaptureDriving {
    var job = CaptureJobFixture()
    var completion: (@Sendable (Int32, ScreenshotFailure?) -> Void)?
    var url: URL?
    var launches = 0
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        self.url = url; self.completion = completion; launches += 1
        return job
    }
}
@MainActor struct ScreenshotRuntimeTests {
    @Test func pauseBackendSecureSessionAndDisableCancelActualManagerClipboardCommit() async throws {
        for change in 0..<6 {
            let driver = CaptureDriverFixture()
            let board = NSPasteboard(name: .init("BridgeCapturePolicy-\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            board.setString("keep original", forType: .string)
            let before = board.changeCount
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
            var coordinator = RuntimePolicyCoordinator()
            var input = RuntimePolicyInput()
            input.backend = .deviceHID; input.shortcutEnabled = true; input.screenshotEnabled = true
            input.foreground = .init(processID: .max, bundleID: "test.fake", mode: .macOS)
            manager.applyRuntimePolicy(coordinator.transition(input), windowsKey: .option, printScreen: .snipping)
            manager.requestCapture(.region)
            #expect(driver.launches == 1)
            switch change {
            case 0: input.paused = true
            case 1: input.backend = .eventTap; input.paused = true // suppress real tap creation in this test
            case 2: input.secureInput = true
            case 3: input.session &+= 1
            case 4: input.screenshotEnabled = false
            default: input.settingsRevision &+= 1
            }
            manager.applyRuntimePolicy(coordinator.transition(input), windowsKey: .option, printScreen: .snipping)
            #expect(driver.job.cancellations.contains(.policyCancelled))
            driver.completion?(0, nil)
            for _ in 0..<5 { await Task.yield() }
            #expect(board.changeCount == before && board.string(forType: .string) == "keep original")
            manager.stop()
        }
    }
    @Test func failureCategoriesSurviveDriverCompletionAndDoNotWriteClipboard() async throws {
        for failure: ScreenshotFailure in [.userCancelled, .permissionDenied, .diskFailure, .processFailure, .timedOut] {
            let driver = CaptureDriverFixture()
            let board = NSPasteboard(name: .init("BridgeCaptureFailure-\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
            var input = RuntimePolicyInput(); input.backend = .deviceHID
            input.shortcutEnabled = true; input.screenshotEnabled = true
            input.foreground = .init(processID: .max, bundleID: "test.fake", mode: .macOS)
            var coordinator = RuntimePolicyCoordinator()
            manager.applyRuntimePolicy(coordinator.transition(input), windowsKey: .option, printScreen: .snipping)
            let before = board.changeCount
            manager.requestCapture(.region)
            driver.completion?(1, failure)
            for _ in 0..<10 { await Task.yield() }
            #expect(manager.status.lastResult == failure.rawValue)
            #expect(board.changeCount == before)
            manager.stop()
        }
    }
    @Test func sourcePolicyReplacementCancelsActualCaptureAndPreventsLateClipboardWrite() async throws {
        let driver = CaptureDriverFixture()
        let board = NSPasteboard(name: .init("BridgeRemoteCapture-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("untouched", forType: .string); let before = board.changeCount
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "test", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        let origin = SourceWorkGate(), frame = SourceWorkGate()
        manager.requestCapture(.fullScreen, source: .init(origin: origin, frame: frame))
        #expect(driver.launches == 1)
        origin.invalidate(); manager.applyInputRouting(.init())
        #expect(driver.job.cancellations.contains(.policyCancelled))
        driver.completion?(0,nil)
        for _ in 0..<10 { await Task.yield() }
        #expect(board.changeCount == before)
        manager.stop()
    }
    @Test func physicalPreferenceChangeCancelsLocalJobButPreservesRemoteJob() {
        for remote in [false,true] {
            let driver = CaptureDriverFixture()
            let board = NSPasteboard(name: .init("BridgeDeviceCapture-\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
            var input = RuntimePolicyInput(); input.backend = .deviceHID; input.shortcutEnabled = true; input.screenshotEnabled = true
            input.foreground = .init(processID: .max, bundleID: "test", mode: .macOS)
            var policy = RuntimePolicyCoordinator()
            manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
            let token = SourceWorkToken(origin: .init(), frame: .init())
            manager.requestCapture(.region, source: remote ? token : nil)
            manager.applyPhysicalPreferences([.init(identity: "a", experience: .nativeMac)])
            #expect(driver.job.cancellations.contains(.policyCancelled) == !remote)
            manager.stop()
        }
    }
}

@MainActor struct ScreenshotProcessingRegressionTests {
    @Test func completedCaptureProducesPasteableImageWithoutOpeningTheFile() async throws {
        let driver = CaptureDriverFixture()
        let board = NSPasteboard(name: .init("BridgeAutomaticCopy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "fixture", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        manager.requestCapture(.region)
        let path = try #require(driver.url)
        defer { try? FileManager.default.removeItem(at: path) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: path)
        driver.completion?(0, nil)
        for _ in 0..<500 where board.data(forType: .init("public.png")) == nil {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(board.data(forType: .init("public.png")) == png)
        #expect(NSImage(pasteboard: board) != nil)
        #expect(manager.status.issue == nil)
    }

    @Test(arguments: [false, true]) func pauseAndResumeDuringDecodeKeepsSingleFlightAndRejectsOldClipboardWrite(native: Bool) async throws {
        let gate = DelayedImagePreparation()
        defer { gate.finish.signal() }
        let driver = CaptureDriverFixture()
        let board = NSPasteboard(name: .init("BridgeDelayedDecode-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("preserved", forType: .string)
        let before = board.changeCount
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            prepareImage: { gate.prepare($0) }, captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "fixture", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        if !native { manager.requestCapture(.region) }
        let path = native ? FileManager.default.temporaryDirectory.appendingPathComponent("NativeDelayed-\(UUID().uuidString).png") : try #require(driver.url)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data([1]).write(to: path)
        if native { manager.acceptNativeScreenshot(path) } else { driver.completion?(0, nil) }
        for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(2)) }
        #expect(gate.started)
        input.paused = true
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        input.paused = false; input.session &+= 1
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        manager.requestCapture(.region)
        let originalLaunches = native ? 0 : 1
        #expect(driver.launches == originalLaunches)
        gate.finish.signal()
        for _ in 0..<500 where driver.launches == originalLaunches {
            try await Task.sleep(for: .milliseconds(2))
            manager.requestCapture(.region)
        }
        #expect(driver.launches == originalLaunches + 1)
        #expect(board.changeCount == before && board.string(forType: .string) == "preserved")
        driver.completion?(1, .userCancelled)
    }

    @Test func nativeScreenshotSurvivesOrdinaryAppSwitchToThePasteDestination() async throws {
        let gate = DelayedImagePreparation(); defer { gate.finish.signal() }
        let board = NSPasteboard(name: .init("BridgeNativeAppChange-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = ScreenshotManager(clipboard: board, authorization: { true }, prepareImage: { gate.prepare($0) },
            captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: 1, bundleID: "fixture.A", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("NativeAppSwitch-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        try Data([1]).write(to: path)
        manager.acceptNativeScreenshot(path)
        for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(2)) }
        #expect(gate.started)
        input.foreground = .init(processID: 2, bundleID: "fixture.B", mode: .terminal)
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        gate.finish.signal()
        for _ in 0..<500 where board.data(forType: .init("public.png")) == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(board.data(forType: .init("public.png")) == Data([137, 80, 78, 71]))
    }
    @Test func selectionFinishedAfterPauseAndResumeCannotStartNewClipboardWork() async throws {
        let gate = DelayedImagePreparation(); defer { gate.finish.signal() }
        let board = NSPasteboard(name: .init("BridgeLateNative-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("preserved", forType: .string)
        let before = board.changeCount
        let manager = ScreenshotManager(clipboard: board, authorization: { true }, prepareImage: { gate.prepare($0) },
            captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: 1, bundleID: "fixture.A", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        manager.noteNativeScreenshotShortcut()
        input.paused = true
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        input.paused = false
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("LateNative-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        try Data([1]).write(to: path)
        manager.acceptNativeScreenshot(path)
        #expect(!gate.started && board.changeCount == before)
        manager.noteNativeScreenshotShortcut()
        manager.acceptNativeScreenshot(path)
        for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(2)) }
        #expect(gate.started)
        gate.finish.signal()
        for _ in 0..<500 where board.data(forType: .init("public.png")) == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(board.data(forType: .init("public.png")) != nil)
    }
    @Test func permissionAndProcessingFailuresAreReportedWithoutClipboardChanges() async throws {
        let board = NSPasteboard(name: .init("BridgeProcessing-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let before = board.changeCount
        let denied = CaptureDriverFixture()
        let manager = ScreenshotManager(driver: denied, clipboard: board, authorization: { false }, captureDirectory: FileManager.default.temporaryDirectory)
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.foreground = .init(processID: .max, bundleID: "test.fake", mode: .macOS)
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "test.fake", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        manager.requestCapture(.region)
        #expect(denied.launches == 0 && manager.status.lastResult == "permissionDenied")
        manager.stop()
        for failure in [ScreenshotFailure.decodeFailure, .encodeFailure] {
            let driver = CaptureDriverFixture()
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, prepareImage: { _ in .failure(failure) }, captureDirectory: FileManager.default.temporaryDirectory)
            manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
            manager.requestCapture(.region)
            let path = try #require(driver.url)
            try Data([1]).write(to: path); defer { try? FileManager.default.removeItem(at: path) }
            driver.completion?(0,nil)
            for _ in 0..<100 where manager.status.lastResult != failure.rawValue { try await Task.sleep(for: .milliseconds(1)) }
            #expect(manager.status.lastResult == failure.rawValue && board.changeCount == before)
            manager.stop()
        }
    }
    @Test func timeoutCancelsAndLateCompletionCannotCommit() async throws {
        let driver = CaptureDriverFixture()
        let board = NSPasteboard(name: .init("BridgeTimeout-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureTimeout: 0.01, captureDirectory: FileManager.default.temporaryDirectory)
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "test.fake", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        manager.requestCapture(.region)
        let before = board.changeCount
        try await Task.sleep(for: .milliseconds(30))
        #expect(driver.job.cancellations.contains(.timedOut))
        driver.completion?(0,nil)
        for _ in 0..<10 { await Task.yield() }
        #expect(manager.status.lastResult == "timedOut" && board.changeCount == before)
        manager.stop()
    }
}

private final class DelayedImagePreparation: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    let finish = DispatchSemaphore(value: 0)
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    func prepare(_ url: URL) -> Result<ScreenshotImagePayload, ScreenshotFailure> {
        lock.lock(); didStart = true; lock.unlock()
        // Parallel model tests can occupy CI's executor for longer than five
        // seconds. Keep the decoder held until the test releases it; retain a
        // bounded fallback for a broken test, not a capture timeout simulation.
        guard finish.wait(timeout: .now() + 60) == .success else { return .failure(.timedOut) }
        return .success(.init(png: Data([137, 80, 78, 71])))
    }
}

private final class TextRecognizerFixture: ScreenshotTextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<String, ScreenshotFailure>
    private var calls = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    init(_ result: Result<String, ScreenshotFailure>) { self.result = result }
    private func take() -> Result<String, ScreenshotFailure> {
        lock.lock(); calls += 1; lock.unlock(); return result
    }
    func recognize(png: Data) async -> Result<String, ScreenshotFailure> { take() }
}
private final class DelayedTextRecognizer: ScreenshotTextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<String, ScreenshotFailure>, Never>?
    private var completed = false, didStart = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    func recognize(png: Data) async -> Result<String, ScreenshotFailure> {
        await withCheckedContinuation { value in
            lock.lock(); didStart = true
            if completed { lock.unlock(); value.resume(returning: .success("late text")) }
            else { continuation = value; lock.unlock() }
        }
    }
    func finish() {
        lock.lock(); completed = true; let value = continuation; continuation = nil; lock.unlock()
        value?.resume(returning: .success("late text"))
    }
}
@MainActor private final class TextCaptureAuthorizationFixture { var granted = true }

@MainActor struct ScreenshotTextCaptureTests {
    private func configure(_ manager: ScreenshotManager) -> (RuntimePolicyCoordinator, RuntimePolicyInput) {
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "test.fake", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        return (policy, input)
    }
    private func complete(_ driver: CaptureDriverFixture) throws {
        let url = try #require(driver.url)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url); driver.completion?(0, nil)
    }
    private func waitUntilIdle(_ manager: ScreenshotManager) async throws {
        for _ in 0..<500 where manager.status.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!manager.status.isBusy)
    }
    @Test func explicitTextCaptureSharesTheSlotAndCopiesOnlyText() async throws {
        let driver = CaptureDriverFixture(), recognizer = TextRecognizerFixture(.success("測試文字 123"))
        let board = NSPasteboard(name: .init("OCRTextCapture-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            captureDirectory: FileManager.default.temporaryDirectory, textRecognizer: recognizer)
        defer { manager.stop() }
        _ = configure(manager)
        manager.requestTextCapture(); manager.requestCapture(.region)
        #expect(driver.launches == 1 && manager.status.isBusy)
        let path = try #require(driver.url)
        try complete(driver); try await waitUntilIdle(manager)
        #expect(board.string(forType: .string) == "測試文字 123")
        #expect(board.data(forType: .init("public.png")) == nil && recognizer.callCount == 1)
        #expect(!manager.status.lastResult.contains("測試文字"), "OCR text never enters status/log strings")
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
    @Test func regularImagesDoNotLaunchTextRecognition() async throws {
        let driver = CaptureDriverFixture(), recognizer = TextRecognizerFixture(.success("unused"))
        let board = NSPasteboard(name: .init("OCRRegularImage-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            captureDirectory: FileManager.default.temporaryDirectory, textRecognizer: recognizer)
        defer { manager.stop() }
        _ = configure(manager); manager.requestCapture(.region)
        try complete(driver); try await waitUntilIdle(manager)
        #expect(board.data(forType: .init("public.png")) != nil && recognizer.callCount == 0)
    }
    @Test func noTextAndRecognitionFailuresPreserveClipboard() async throws {
        for failure: ScreenshotFailure in [.textNotFound,.recognitionFailure,.textTooLarge] {
            let driver = CaptureDriverFixture(), recognizer = TextRecognizerFixture(.failure(failure))
            let board = NSPasteboard(name: .init("OCRFailure-\(UUID().uuidString)")); defer { board.releaseGlobally() }
            board.setString("keep", forType: .string); let before = board.changeCount
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
                captureDirectory: FileManager.default.temporaryDirectory, textRecognizer: recognizer)
            defer { manager.stop() }
            _ = configure(manager); manager.requestTextCapture()
            try complete(driver); try await waitUntilIdle(manager)
            #expect(manager.status.lastResult == failure.rawValue)
            #expect(board.changeCount == before && board.string(forType: .string) == "keep")
        }
    }
    @Test func cancelPauseAndSessionChangeRejectLateTextAndRetainSingleFlight() async throws {
        for transition in 0..<3 {
            let driver = CaptureDriverFixture(), gate = DelayedTextRecognizer(); defer { gate.finish() }
            let board = NSPasteboard(name: .init("OCRLateResult-\(UUID().uuidString)")); defer { board.releaseGlobally() }
            board.setString("original", forType: .string); let before = board.changeCount
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
                captureDirectory: FileManager.default.temporaryDirectory, textRecognizer: gate)
            defer { manager.stop() }
            var (policy, input) = configure(manager)
            manager.requestTextCapture(); try complete(driver)
            for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(10)) }
            #expect(gate.started && manager.status.recognizingText)
            switch transition {
            case 0: manager.cancelCapture()
            case 1: input.paused = true
            default: input.session &+= 1
            }
            manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
            input.paused = false
            manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
            manager.requestTextCapture()
            #expect(driver.launches == 1 && manager.status.isBusy)
            gate.finish(); try await waitUntilIdle(manager)
            #expect(board.changeCount == before && board.string(forType: .string) == "original")
            manager.requestCapture(.region); #expect(driver.launches == 2)
            driver.completion?(1, .userCancelled); try await waitUntilIdle(manager)
        }
    }
    @Test func permissionRevocationDuringRecognitionBlocksClipboardCommit() async throws {
        let access = TextCaptureAuthorizationFixture()
        let driver = CaptureDriverFixture(), gate = DelayedTextRecognizer(); defer { gate.finish() }
        let board = NSPasteboard(name: .init("OCRPermission-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        board.setString("keep", forType: .string); let before = board.changeCount
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { access.granted },
            captureDirectory: FileManager.default.temporaryDirectory, textRecognizer: gate)
        defer { manager.stop() }
        _ = configure(manager); manager.requestTextCapture(); try complete(driver)
        for _ in 0..<500 where !gate.started { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.started)
        access.granted = false; gate.finish(); try await waitUntilIdle(manager)
        #expect(manager.status.lastResult == "permissionDenied" && board.changeCount == before)
    }
}
