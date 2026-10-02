import AppKit
import Testing
import BridgeCore
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
        #expect(manager.status.lastResult.contains("可直接按"))
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
        guard finish.wait(timeout: .now() + 5) == .success else { return .failure(.timedOut) }
        return .success(.init(png: Data([137, 80, 78, 71])))
    }
}
