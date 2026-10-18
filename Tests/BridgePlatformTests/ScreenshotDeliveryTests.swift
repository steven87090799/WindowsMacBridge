import AppKit
import Testing
import BridgeCore
@testable import BridgePlatform

private final class DeliveryJob: ScreenshotCaptureJob, @unchecked Sendable {
    func cancel(_ reason: ScreenshotFailure) {}
    func noteUserCancellation() {}
}
@MainActor private final class DeliveryDriver: ScreenshotCaptureDriving {
    var url: URL?
    var completion: (@Sendable (Int32, ScreenshotFailure?) -> Void)?
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        self.url = url; self.completion = completion; return DeliveryJob()
    }
}
private final class ThumbnailBarrier: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entered = false
    var hasEntered: Bool { lock.withLock { entered } }
    func prepare(_ png: Data) -> Data? {
        lock.withLock { entered = true }
        _ = release.wait(timeout: .now() + 10)
        return ScreenshotPreviewPreparation.thumbnail(png: png)
    }
}

@MainActor struct ScreenshotDeliveryTests {
    private func configure(_ manager: ScreenshotManager) -> (RuntimePolicyCoordinator, RuntimePolicyInput) {
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "fixture", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        return (policy, input)
    }
    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test(arguments: ScreenshotKind.allCases) func capturesNeverWaitForNativeFloatingThumbnail(kind: ScreenshotKind) throws {
        let url = URL(fileURLWithPath: "/tmp/owned-screenshot.png")
        let arguments = try NativeScreenshotCaptureDriver.arguments(kind: kind, destination: url, windowID: 42)
        #expect(!arguments.contains("-u") && !arguments.contains("-p"))
        #expect(arguments.first == "-x" && arguments.last == url.path)
        if kind == .region { #expect(arguments == ["-x", "-t", "png", "-i", "-s", url.path]) }
        if kind == .activeWindow { #expect(arguments == ["-x", "-t", "png", "-l", "42", url.path]) }
        #expect(throws: ScreenshotFailure.processFailure) {
            try NativeScreenshotCaptureDriver.arguments(kind: .activeWindow, destination: url)
        }
    }

    @Test func clipboardCommitsWhileThumbnailPreparationIsBlocked() async throws {
        let board = NSPasteboard(name: .init("FastDelivery-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        board.setString("previous fixture", forType: .string)
        let driver = DeliveryDriver(), barrier = ThumbnailBarrier()
        defer { barrier.release.signal() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            captureDirectory: FileManager.default.temporaryDirectory, prepareThumbnail: barrier.prepare)
        defer { manager.stop() }
        _ = configure(manager)
        var previews = [ScreenshotPreview]()
        manager.onPreviewReady = { previews.append($0); return false }
        manager.requestCapture(.region)
        let url = try #require(driver.url); let bytes = try png(); try bytes.write(to: url)
        driver.completion?(0, nil)
        for _ in 0..<500 where !barrier.hasEntered { try await Task.sleep(for: .milliseconds(2)) }
        #expect(barrier.hasEntered)
        #expect(board.data(forType: .init("public.png")) == bytes)
        #expect(!manager.status.isBusy && manager.status.lastResult == "截圖已複製，可直接貼上")
        #expect(previews.isEmpty)
        barrier.release.signal()
        for _ in 0..<500 where previews.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        #expect(previews.count == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func pauseAfterCopySuppressesThePendingThumbnail() async throws {
        let board = NSPasteboard(name: .init("PausedPreview-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = DeliveryDriver(), barrier = ThumbnailBarrier()
        defer { barrier.release.signal() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            captureDirectory: FileManager.default.temporaryDirectory, prepareThumbnail: barrier.prepare)
        defer { manager.stop() }
        var (policy, input) = configure(manager)
        var count = 0; manager.onPreviewReady = { _ in count += 1; return false }
        manager.requestCapture(.region); let url = try #require(driver.url)
        let bytes = try png(); try bytes.write(to: url); driver.completion?(0, nil)
        for _ in 0..<500 where !barrier.hasEntered { try await Task.sleep(for: .milliseconds(2)) }
        #expect(barrier.hasEntered && board.data(forType: .init("public.png")) == bytes)
        input.paused = true
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        barrier.release.signal()
        for _ in 0..<500 where FileManager.default.fileExists(atPath: url.path) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(count == 0 && !FileManager.default.fileExists(atPath: url.path))
        #expect(board.data(forType: .init("public.png")) == bytes)
    }

    @Test func newerCaptureReplacesAPendingPreviewWithoutRevertingClipboard() async throws {
        let board = NSPasteboard(name: .init("NewPreview-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = DeliveryDriver(), barrier = ThumbnailBarrier()
        defer { barrier.release.signal(); barrier.release.signal() }
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            captureDirectory: FileManager.default.temporaryDirectory, prepareThumbnail: barrier.prepare)
        defer { manager.stop() }
        _ = configure(manager)
        var previews = [URL](); manager.onPreviewReady = { previews.append($0.sourceURL); return false }
        manager.requestCapture(.region); let first = try #require(driver.url)
        let bytes = try png(); try bytes.write(to: first); driver.completion?(0, nil)
        for _ in 0..<500 where !barrier.hasEntered { try await Task.sleep(for: .milliseconds(2)) }
        #expect(barrier.hasEntered && board.data(forType: .init("public.png")) == bytes)
        manager.requestCapture(.region); let second = try #require(driver.url)
        #expect(first != second)
        try bytes.write(to: second); driver.completion?(0, nil)
        barrier.release.signal(); barrier.release.signal()
        for _ in 0..<500 where previews.isEmpty || FileManager.default.fileExists(atPath: first.path) {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(previews == [second])
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(board.data(forType: .init("public.png")) == bytes)
    }

    @Test func savedFullScreenOriginalSurvivesDeclinedPreview() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("SavedOriginal-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = DeliveryDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        _ = configure(manager)
        var shown = false; manager.onPreviewReady = { value in shown = true; #expect(!value.ownsSourceFile); return false }
        manager.requestCapture(.fullScreenSave); let url = try #require(driver.url)
        try png().write(to: url); driver.completion?(0, nil)
        for _ in 0..<500 where !shown { try await Task.sleep(for: .milliseconds(2)) }
        #expect(shown && FileManager.default.fileExists(atPath: url.path))
    }

    @Test func nativeUserSaveInTemporaryFolderIsNeverOwned() async throws {
        let board = NSPasteboard(name: .init("NativeOwnership-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let manager = ScreenshotManager(clipboard: board, authorization: { true })
        defer { manager.stop() }
        _ = configure(manager)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-user-save-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try png(); try bytes.write(to: url)
        manager.acceptNativeScreenshot(url)
        for _ in 0..<500 where manager.status.isBusy { try await Task.sleep(for: .milliseconds(2)) }
        #expect(board.data(forType: .init("public.png")) == bytes)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
