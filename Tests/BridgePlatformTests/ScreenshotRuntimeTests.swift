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
