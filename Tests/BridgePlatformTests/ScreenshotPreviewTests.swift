import AppKit
import ImageIO
import Testing
import BridgeCore
@testable import BridgePlatform

private final class PreviewCaptureJob: ScreenshotCaptureJob, @unchecked Sendable {
    func cancel(_ reason: ScreenshotFailure) {}
    func noteUserCancellation() {}
}
@MainActor private final class PreviewCaptureDriver: ScreenshotCaptureDriving {
    var url: URL?
    var completion: (@Sendable (Int32, ScreenshotFailure?) -> Void)?
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        self.url = url; self.completion = completion; return PreviewCaptureJob()
    }
}
private struct PreviewTextRecognizer: ScreenshotTextRecognizing {
    func recognize(png: Data) async -> Result<String, ScreenshotFailure> { .success("recognized fixture") }
}

@MainActor struct ScreenshotPreviewTests {
    private func configure(_ manager: ScreenshotManager) -> (RuntimePolicyCoordinator, RuntimePolicyInput) {
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "fixture", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        return (policy,input)
    }
    private func png(width: Int = 8, height: Int = 8) throws -> Data {
        let image = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        image.setFillColor(CGColor(gray: 0.5, alpha: 1)); image.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let result = try #require(image.makeImage())
        return try ScreenshotImagePreparation.encodePNG(result).get().png
    }
    private func wait(_ manager: ScreenshotManager) async throws {
        for _ in 0..<500 where manager.status.isBusy { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!manager.status.isBusy)
    }

    @Test(arguments: ScreenshotKind.allCases) func completedImagePublishesPreviewAfterClipboardCommit(kind: ScreenshotKind) async throws {
        let board = NSPasteboard(name: .init("PreviewCommit-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = PreviewCaptureDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        _ = configure(manager)
        var previews = [ScreenshotPreview]()
        manager.onPreviewReady = { preview in
            #expect(board.data(forType: .init("public.png")) != nil)
            previews.append(preview); return true
        }
        manager.requestCapture(kind)
        let url = try #require(driver.url); defer { try? FileManager.default.removeItem(at: url) }
        try png().write(to: url); driver.completion?(0,nil)
        try await wait(manager)
        for _ in 0..<500 where previews.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        let preview = try #require(previews.first)
        #expect(previews.count == 1 && preview.ownsSourceFile && preview.sourceURL == url)
        #expect(preview.thumbnailPNG.count <= ScreenshotPreviewPreparation.maximumPNGBytes)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func declinedPreviewDoesNotLeakTheTemporaryOriginal() async throws {
        let board = NSPasteboard(name: .init("PreviewDecline-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = PreviewCaptureDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        _ = configure(manager); manager.onPreviewReady = { _ in false }
        manager.requestCapture(.region); let url = try #require(driver.url)
        try png().write(to: url); driver.completion?(0,nil); try await wait(manager)
        for _ in 0..<500 where FileManager.default.fileExists(atPath: url.path) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(board.data(forType: .init("public.png")) != nil)
    }

    @Test func cancelledCaptureNeverShowsALatePreview() async throws {
        let board = NSPasteboard(name: .init("PreviewCancel-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = PreviewCaptureDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: FileManager.default.temporaryDirectory)
        defer { manager.stop() }
        _ = configure(manager); var count = 0
        manager.onPreviewReady = { _ in count += 1; return false }
        manager.requestCapture(.region); let url = try #require(driver.url)
        try png().write(to: url); manager.cancelCapture(); driver.completion?(0,nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(count == 0 && board.data(forType: .init("public.png")) == nil)
    }

    @Test func textRecognitionNeverRequestsAnImagePreview() async throws {
        let board = NSPasteboard(name: .init("PreviewOCR-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = PreviewCaptureDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true },
            captureDirectory: FileManager.default.temporaryDirectory, textRecognizer: PreviewTextRecognizer(), textRecognitionEnabled: true)
        defer { manager.stop() }
        _ = configure(manager); var count = 0
        manager.onPreviewReady = { _ in count += 1; return false }
        manager.requestTextCapture(); let url = try #require(driver.url)
        try png().write(to: url); driver.completion?(0,nil); try await wait(manager)
        #expect(count == 0 && board.string(forType: .string) == "recognized fixture")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func existingNativeFileUsesItsSystemThumbnailAndIsNotOwned() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: .init("PreviewNative-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let manager = ScreenshotManager(clipboard: board, authorization: { true }, captureDirectory: directory)
        defer { manager.stop() }
        _ = configure(manager); var count = 0
        manager.onPreviewReady = { _ in count += 1; return false }
        let url = directory.appendingPathComponent("native.png"); try png().write(to: url)
        manager.acceptNativeScreenshot(url); try await wait(manager)
        #expect(count == 0 && FileManager.default.fileExists(atPath: url.path))
        #expect(board.data(forType: .init("public.png")) != nil)
    }

    @Test func thumbnailIsBoundedBeforeItReachesTheUI() throws {
        let bytes = try png(width: 2400, height: 1600)
        let thumbnail = try #require(ScreenshotPreviewPreparation.thumbnail(png: bytes))
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData,nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source,0,nil))
        #expect(image.width <= ScreenshotPreviewPreparation.maximumDimension && image.height <= ScreenshotPreviewPreparation.maximumDimension && thumbnail.count <= 1024 * 1024)
        #expect(ScreenshotPreviewPreparation.thumbnail(png: Data("invalid".utf8)) == nil)
    }
}
