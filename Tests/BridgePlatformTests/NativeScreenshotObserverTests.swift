import AppKit
import Darwin
import Testing
import BridgeCore
@testable import BridgePlatform

private final class ObserverReleaseBox: @unchecked Sendable {
    var observer: NativeScreenshotObserver?
    init(_ observer: NativeScreenshotObserver) { self.observer = observer }
}

@MainActor struct NativeScreenshotObserverTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeNativeObserver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func mark(_ url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, data.count, 0, 0) }
        #expect(result == 0)
    }
    @Test func backgroundReleaseDoesNotKeepObserverOrDeliverLateFiles() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var observer: NativeScreenshotObserver? = NativeScreenshotObserver()
        weak var released = observer
        var deliveries = 0
        observer?.onScreenshot = { _ in deliveries += 1 }
        #expect(observer?.start(directory: folder) == true)
        let box = ObserverReleaseBox(try #require(observer))
        observer = nil
        await Task.detached { box.observer = nil }.value
        #expect(released == nil)
        let file = folder.appendingPathComponent("after-release.png")
        try Data([1]).write(to: file); try mark(file)
        try await Task.sleep(for: .milliseconds(350))
        #expect(deliveries == 0)
    }
    @Test func onlyNewNativeMarkedFilesInTheConfiguredFolderAreEligible() throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("native.png")
        let since = Date().addingTimeInterval(-1)
        try Data([1]).write(to: path)
        #expect(NativeScreenshotObserver.screenshotDate(path, directory: folder, since: since) == nil)
        try mark(path)
        #expect(NativeScreenshotObserver.screenshotDate(path, directory: folder, since: since) != nil)
        #expect(NativeScreenshotObserver.screenshotDate(path, directory: folder, since: Date().addingTimeInterval(1)) == nil)
        #expect(NativeScreenshotObserver.screenshotDate(path, directory: folder.appendingPathComponent("different"), since: since) == nil)
        let link = folder.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
        #expect(NativeScreenshotObserver.screenshotDate(link, directory: folder, since: since) == nil)
        let own = folder.appendingPathComponent("WindowsMacBridge Screenshot fixture.png")
        try FileManager.default.copyItem(at: path, to: own)
        #expect(NativeScreenshotObserver.screenshotDate(own, directory: folder, since: since) == nil)
    }
    @Test func nativeFileEventCopiesImageOnceAndStopDoesNotReplayFiles() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("BridgeNativeEvent-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = ScreenshotManager(clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "fixture", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .option, printScreen: .snipping)
        let observer = NativeScreenshotObserver()
        defer { observer.stop() }
        var deliveries = 0
        observer.onScreenshot = { url in deliveries += 1; manager.acceptNativeScreenshot(url) }
        #expect(observer.start(directory: folder))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let path = folder.appendingPathComponent("native.png")
        try png.write(to: path); try mark(path)
        for _ in 0..<500 where board.data(forType: .init("public.png")) == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(board.data(forType: .init("public.png")) == png)
        #expect(deliveries == 1)
        observer.stop()
        let before = board.changeCount
        let second = folder.appendingPathComponent("while-stopped.png")
        try png.write(to: second); try mark(second)
        #expect(observer.start(directory: folder))
        try await Task.sleep(for: .milliseconds(350))
        #expect(deliveries == 1 && board.changeCount == before)
    }
}
