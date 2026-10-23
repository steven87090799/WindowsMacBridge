import AppKit
import Quartz

/// Quick Look belongs to our window, so a thumbnail click can activate and
/// position it synchronously instead of launching a background qlmanage App.
@MainActor public final class ScreenshotPreviewWindow: NSObject, NSWindowDelegate {
    public let window: NSWindow
    private let previewView: QLPreviewView
    private let sourceURL: URL
    private let clipboard: NSPasteboard
    private var copyTask: Task<Void, Never>?
    private var closed = false
    public var onClose: (() -> Void)?

    public init(sourceURL: URL, imageSize: NSSize, visibleFrame: NSRect,
                clipboard: NSPasteboard = .general) {
        self.sourceURL = sourceURL; self.clipboard = clipboard
        let frame = Self.frame(imageSize: imageSize, visibleFrame: visibleFrame)
        let viewer = ScreenshotViewerWindow(contentRect: .init(origin: .zero, size: frame.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window = viewer
        previewView = QLPreviewView(frame: .init(origin: .zero, size: frame.size), style: .normal)
        super.init()
        viewer.isReleasedWhenClosed = false
        viewer.title = "截圖預覽"
        viewer.minSize = NSSize(width: 320, height: 240)
        viewer.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        viewer.contentView = previewView
        // We release the preview explicitly before its owned source is removed.
        // Quick Look's automatic window-close observer must not close it twice.
        previewView.shouldCloseWithWindow = false
        viewer.delegate = self
        viewer.copyImage = { [weak self] in self?.copyImage() }
        previewView.previewItem = sourceURL as NSURL
        viewer.setFrame(frame, display: false)
    }

    public static func frame(imageSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let available = NSSize(width: max(1, min(1200, visibleFrame.width * 0.85)),
                               height: max(1, min(900, visibleFrame.height * 0.85)))
        let ratio = min(available.width / max(1, imageSize.width), available.height / max(1, imageSize.height))
        let size = NSSize(width: min(available.width, max(320, imageSize.width * ratio)),
                          height: min(available.height, max(240, imageSize.height * ratio)))
        return NSRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    public func close() { window.close() }

    public func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        copyTask?.cancel(); copyTask = nil
        previewView.close()
        window.contentView = nil
        let completion = onClose; onClose = nil
        completion?()
    }

    private func copyImage() {
        guard !closed else { return }
        copyTask?.cancel()
        let sourceURL = sourceURL
        copyTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { ScreenshotImagePreparation.prepare(at: sourceURL) }
            let payload = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, let payload else { return }
            _ = ScreenshotClipboard.write(payload, to: clipboard)
        }
    }
}

@MainActor private final class ScreenshotViewerWindow: NSWindow {
    var copyImage: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == 8, flags == .control || flags == .command {
            copyImage?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || (event.keyCode == 49 && event.modifierFlags.intersection([.control, .command, .option, .shift]).isEmpty) {
            close(); return
        }
        super.keyDown(with: event)
    }
}
