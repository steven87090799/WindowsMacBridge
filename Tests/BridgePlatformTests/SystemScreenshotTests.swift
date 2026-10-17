import AppKit
import Darwin
import Testing
import BridgeCore
@testable import BridgePlatform

private final class SystemUIJob: ScreenshotCaptureJob, @unchecked Sendable {
    func cancel(_ reason: ScreenshotFailure) {}
    func noteUserCancellation() {}
}
@MainActor private final class SystemUIDriver: SystemScreenshotCaptureDriving {
    var fileLaunches = 0
    var uiKinds: [ScreenshotKind] = []
    var fileURL: URL?
    var completion: (@Sendable (Int32, ScreenshotFailure?) -> Void)?
    func launch(to url: URL, kind: ScreenshotKind, processID: Int32,
                completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        fileLaunches += 1; fileURL = url; self.completion = completion; return SystemUIJob()
    }
    func launchSystemUI(kind: ScreenshotKind, processID: Int32,
                        completion: @escaping @Sendable (Int32, ScreenshotFailure?) -> Void) throws -> any ScreenshotCaptureJob {
        uiKinds.append(kind); self.completion = completion; return SystemUIJob()
    }
}

@MainActor struct SystemScreenshotTests {
    @Test func systemArgumentsDelegatePresentationAndStorageWhileOCRStaysPrivate() throws {
        #expect(try NativeScreenshotCaptureDriver.arguments(kind: .region, destination: nil) == ["-u", "-p", "-i"])
        #expect(try NativeScreenshotCaptureDriver.arguments(kind: .fullScreen, destination: nil) == ["-u", "-p"])
        #expect(try NativeScreenshotCaptureDriver.arguments(kind: .fullScreenSave, destination: nil) == ["-u", "-p"])
        #expect(try NativeScreenshotCaptureDriver.arguments(kind: .activeWindow, destination: nil, windowID: 42) == ["-u", "-p", "-l", "42"])
        let url = URL(fileURLWithPath: "/tmp/private-ocr.png")
        #expect(try NativeScreenshotCaptureDriver.arguments(kind: .region, destination: url) == ["-x", "-t", "png", "-i", "-s", url.path])
        #expect(throws: ScreenshotFailure.processFailure) {
            try NativeScreenshotCaptureDriver.arguments(kind: .activeWindow, destination: nil)
        }
    }
    private func configure(_ manager: ScreenshotManager) -> (RuntimePolicyCoordinator, RuntimePolicyInput) {
        var input = RuntimePolicyInput(); input.backend = .deviceHID
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: .max, bundleID: "fixture", mode: .macOS)
        var policy = RuntimePolicyCoordinator()
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        return (policy, input)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SystemUI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func save(_ url: URL, marked: Bool = true) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        if marked {
            let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            #expect(data.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, data.count, 0, 0) } == 0)
        }
        return png
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(450)) }
    private func waitForCopy(_ board: NSPasteboard) async throws {
        for _ in 0..<500 where board.data(forType: .init("public.png")) == nil { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test(arguments: ScreenshotKind.allCases) func imageCapturesUseSystemUIAndDoNotRequireAPrivateOutput(kind: ScreenshotKind) async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("SystemUIRoute-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        board.setString("keep", forType: .string)
        let driver = SystemUIDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        _ = configure(manager); manager.requestCapture(kind)
        #expect(driver.uiKinds == [kind] && driver.fileLaunches == 0)
        driver.completion?(0, nil); try await settle()
        #expect(!manager.status.isBusy && manager.status.issue == nil)
        #expect(board.string(forType: .string) == "keep")
        // A user may leave Markup open, share or delete without saving. It must
        // not hold the capture slot or classify a missing private file as failure.
        manager.requestCapture(kind)
        #expect(driver.uiKinds.count == 2)
        driver.completion?(1, .userCancelled)
    }

    @Test(arguments: [false, true]) func nativeSavedFileCopiesOnceWhetherItPrecedesOrFollowsProcessExit(fileFirst: Bool) async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("SystemUISave-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = SystemUIDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        _ = configure(manager); manager.requestCapture(.region)
        let url = folder.appendingPathComponent("edited-native.png")
        if !fileFirst { driver.completion?(0, nil); try await settle() }
        let bytes = try save(url)
        if fileFirst { try await settle(); driver.completion?(0, nil) }
        try await waitForCopy(board)
        #expect(board.data(forType: .init("public.png")) == bytes)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let count = board.changeCount
        try bytes.write(to: url); try await settle()
        #expect(board.changeCount == count)
    }

    @Test func pauseResumeDiscardsLateSystemFileAndANewCaptureCanCopy() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("SystemUIPause-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        board.setString("keep", forType: .string)
        let driver = SystemUIDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        var (policy, input) = configure(manager); manager.requestCapture(.region)
        driver.completion?(0, nil); try await settle()
        input.paused = true; manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        input.paused = false; manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        _ = try save(folder.appendingPathComponent("late.png")); try await settle()
        #expect(board.string(forType: .string) == "keep")
        manager.requestCapture(.fullScreen); driver.completion?(0, nil); try await settle()
        let bytes = try save(folder.appendingPathComponent("current.png")); try await waitForCopy(board)
        #expect(board.data(forType: .init("public.png")) == bytes)
    }

    @Test func systemEditorAndPasteDestinationAppSwitchesPreserveThePendingSave() async throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("SystemUIAppSwitch-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = SystemUIDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        var (policy, input) = configure(manager); manager.requestCapture(.region)
        input.foreground = .init(processID: .max - 1, bundleID: "com.apple.screencaptureui", mode: .macOS)
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        driver.completion?(0, nil); try await settle()
        input.foreground = .init(processID: .max - 2, bundleID: "fixture.paste", mode: .macOS)
        manager.applyRuntimePolicy(policy.transition(input), windowsKey: .command, printScreen: .snipping)
        let bytes = try save(folder.appendingPathComponent("after-markup.png")); try await waitForCopy(board)
        #expect(board.data(forType: .init("public.png")) == bytes)
    }

    @Test func unrelatedImageAndFailedOrRevokedSystemCaptureNeverReplaceClipboard() async throws {
        for revoked in [false, true] {
            let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let board = NSPasteboard(name: .init("SystemUIReject-\(UUID().uuidString)")); defer { board.releaseGlobally() }
            board.setString("keep", forType: .string)
            let driver = SystemUIDriver()
            let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
            defer { manager.stop() }
            _ = configure(manager)
            let origin = SourceWorkGate()
            let source = SourceWorkToken(origin: origin, frame: .init())
            manager.requestCapture(.region, source: source)
            _ = try save(folder.appendingPathComponent("unrelated.png"), marked: false)
            if revoked { origin.invalidate(); driver.completion?(0, nil) }
            else { driver.completion?(1, .userCancelled) }
            try await settle()
            _ = try save(folder.appendingPathComponent("late-native.png")); try await settle()
            #expect(board.string(forType: .string) == "keep")
        }
    }

    @Test func textRecognitionKeepsPrivateCaptureAndNeverOpensSystemImageUI() throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let board = NSPasteboard(name: .init("SystemUIOCR-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let driver = SystemUIDriver()
        let manager = ScreenshotManager(driver: driver, clipboard: board, authorization: { true }, captureDirectory: folder)
        defer { manager.stop() }
        _ = configure(manager); manager.requestTextCapture()
        #expect(driver.fileLaunches == 1 && driver.uiKinds.isEmpty && driver.fileURL != nil)
        driver.completion?(1, .userCancelled)
    }

    @Test func nativeSaveInTheTemporaryDirectoryIsNeverDeletedByLocation() async throws {
        let board = NSPasteboard(name: .init("SystemUITempSave-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let manager = ScreenshotManager(clipboard: board, authorization: { true })
        defer { manager.stop() }
        _ = configure(manager)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-user-save-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try save(url)
        manager.acceptNativeScreenshot(url); try await waitForCopy(board)
        #expect(board.data(forType: .init("public.png")) == bytes)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
