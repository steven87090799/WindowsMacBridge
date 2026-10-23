import AppKit
import Testing
@testable import BridgePlatform

@MainActor struct ScreenshotPreviewWindowTests {
    @Test func controlAndCommandCopyTheFullImageAndCloseReleasesQuickLook() async throws {
        _ = NSApplication.shared
        let pixels = try #require(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixels.setFillColor(CGColor(gray: 0.5, alpha: 1)); pixels.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let png = try ScreenshotImagePreparation.encodePNG(#require(pixels.makeImage())).get().png
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-window-\(UUID().uuidString).png")
        try png.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let board = NSPasteboard(name: .init("PreviewWindow-\(UUID().uuidString)")); defer { board.releaseGlobally() }
        let viewer = ScreenshotPreviewWindow(sourceURL: url, imageSize: .init(width: 32, height: 24),
            visibleFrame: .init(x: 0, y: 0, width: 1440, height: 900), clipboard: board)
        var closes = 0
        viewer.onClose = { closes += 1 }
        // Offline window only: no activation, global input or user clipboard.
        #expect(!viewer.window.isVisible)
        for flags: NSEvent.ModifierFlags in [.control, .command] {
            board.clearContents()
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: viewer.window.windowNumber, context: nil,
                characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
            #expect(viewer.window.performKeyEquivalent(with: event))
            for _ in 0..<500 where board.data(forType: .init("public.png")) == nil {
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(board.data(forType: .init("public.png")) != nil)
        }
        viewer.close()
        #expect(closes == 1)
        #expect(viewer.window.contentView == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
    @Test func previewCentersOnTheClickedDisplayAndFitsInsideItsUsableArea() {
        for screen in [NSRect(x: 0, y: 50, width: 1440, height: 850),
                       NSRect(x: -2560, y: 0, width: 2560, height: 1440),
                       NSRect(x: 1440, y: -900, width: 900, height: 1440)] {
            for image in [NSSize(width: 3840, height: 2160), NSSize(width: 800, height: 2200), .zero] {
                let frame = ScreenshotPreviewWindow.frame(imageSize: image, visibleFrame: screen)
                #expect(screen.contains(frame))
                #expect(abs(frame.midX - screen.midX) < 0.001)
                #expect(abs(frame.midY - screen.midY) < 0.001)
            }
        }
    }
}
