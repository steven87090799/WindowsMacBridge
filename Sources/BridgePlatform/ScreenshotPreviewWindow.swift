import AppKit
import ImageIO
import BridgeCore

/// The preview belongs to our window, so a thumbnail click can activate and
/// position it synchronously without launching a background qlmanage App.
@MainActor public final class ScreenshotPreviewWindow: NSObject, NSWindowDelegate {
    public let window: NSWindow
    private let imageView: NSImageView
    private let sourceURL: URL
    private let clipboard: NSPasteboard
    private var copyTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var closed = false
    public var onClose: (() -> Void)?

    public init(sourceURL: URL, imageSize: NSSize, visibleFrame: NSRect,
                clipboard: NSPasteboard = .general, thumbnail: NSImage? = nil) {
        self.sourceURL = sourceURL; self.clipboard = clipboard
        let frame = Self.frame(imageSize: imageSize, visibleFrame: visibleFrame)
        let viewer = ScreenshotViewerWindow(contentRect: .init(origin: .zero, size: frame.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window = viewer
        imageView = NSImageView(frame: .init(origin: .zero, size: frame.size))
        super.init()
        viewer.isReleasedWhenClosed = false
        viewer.title = "截圖預覽"
        viewer.minSize = NSSize(width: 320, height: 240)
        viewer.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let scroll = NSScrollView(frame: imageView.frame)
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.25; scroll.maxMagnification = 4
        scroll.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.image = thumbnail
        imageView.setAccessibilityLabel("截圖預覽")
        scroll.documentView = imageView
        viewer.contentView = scroll
        viewer.delegate = self
        viewer.copyImage = { [weak self] in self?.copyImage() }
        viewer.setFrame(frame, display: false)
        imageTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { Self.displayImage(at: sourceURL) }
            let image = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, let image else { return }
            imageView.image = NSImage(cgImage: image, size: .init(width: image.width, height: image.height))
        }
    }

    /// Decode only display-sized pixels on demand. The full-resolution original
    /// stays on disk for Copy. No QuickLook/Vision framework enters the GUI.
    nonisolated static func displayImage(at url: URL) -> CGImage? {
        autoreleasepool {
            guard !Task.isCancelled,
                  let file = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  file.isRegularFile == true, file.isSymbolicLink != true,
                  let bytes = file.fileSize, bytes > 0, bytes <= ImageMemoryBudget.maximumFileBytes,
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, (1...16).contains(depth),
                  ImageMemoryBudget.allows(width: width, height: height, bytesPerPixel: 4 * ((depth + 7) / 8)) else { return nil }
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            return Task.isCancelled ? nil : image
        }
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
        imageTask?.cancel(); imageTask = nil
        imageView.image = nil
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
