import AppKit
import Darwin
import BridgePlatform

/// No window, model, observer or repeating timer exists before an image arrives.
/// One small thumbnail and at most one user-requested system Quick Look process.
@MainActor final class ScreenshotThumbnailPresenter: NSObject {
    private var panel: NSPanel?
    private var preview: ScreenshotPreview?
    private var expiration: DispatchWorkItem?
    private var quickLook: Process?
    private var openedURL: URL?
    private var pendingOpen = false
    private var terminatingQuickLook = false

    func present(_ value: ScreenshotPreview) -> Bool {
        dismiss()
        guard value.thumbnailPNG.count <= ScreenshotPreviewPreparation.maximumPNGBytes,
              let image = NSImage(data: value.thumbnailPNG) else { return false }
        preview = value
        let content = ScreenshotThumbnailView(image: image, target: self,
            openAction: #selector(openPreview), closeAction: #selector(closePreview),
            onHover: { [weak self] hovering in
                guard let self else { return }
                if hovering { self.expiration?.cancel(); self.expiration = nil }
                else { self.scheduleExpiration() }
            })
        let window = NSPanel(contentRect: content.bounds, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false
        window.backgroundColor = .clear; window.hasShadow = true
        window.hidesOnDeactivate = false; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.sharingType = .none
        window.contentView = content
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        window.setFrameOrigin(NSPoint(x: max(frame.minX, frame.maxX - content.bounds.width - 24), y: frame.minY + 24))
        panel = window; window.orderFrontRegardless()
        scheduleExpiration()
        return true
    }

    private func scheduleExpiration() {
        expiration?.cancel()
        let expectedURL = preview?.sourceURL
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.preview?.sourceURL == expectedURL, self.openedURL != expectedURL else { return }
                self.dismiss()
            }
        }
        expiration = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    @objc private func closePreview() { dismiss() }
    func dismiss() {
        expiration?.cancel(); expiration = nil; pendingOpen = false
        panel?.contentView = nil; panel?.close(); panel = nil
        if let value = preview, value.ownsSourceFile, value.sourceURL != openedURL {
            try? FileManager.default.removeItem(at: value.sourceURL)
        }
        preview = nil
        if let child = quickLook, child.isRunning, !terminatingQuickLook {
            terminatingQuickLook = true
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak child] in
                if let child, child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    @objc private func openPreview() {
        guard let value = preview else { return }
        // A previous preview is still retiring: wait for its exit, never spawn
        // another viewer while that owned process is alive.
        if quickLook != nil { pendingOpen = true; expiration?.cancel(); expiration = nil; return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        child.arguments = ["-p", value.sourceURL.path]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        let sourceURL = value.sourceURL, ownsFile = value.ownsSourceFile
        child.terminationHandler = { [weak self] finished in
            if ownsFile { try? FileManager.default.removeItem(at: sourceURL) }
            Task { @MainActor [weak self] in
                guard let self, self.quickLook === finished else { return }
                self.quickLook = nil; self.openedURL = nil; self.terminatingQuickLook = false
                if self.preview?.sourceURL == sourceURL { self.dismiss() }
                if self.pendingOpen { self.pendingOpen = false; self.openPreview() }
            }
        }
        quickLook = child; openedURL = sourceURL; terminatingQuickLook = false
        do {
            try child.run()
            expiration?.cancel(); expiration = nil
            panel?.contentView = nil; panel?.close(); panel = nil
        } catch {
            child.terminationHandler = nil; quickLook = nil; openedURL = nil; terminatingQuickLook = false
            scheduleExpiration()
        }
    }
}

/// A larger, bounded card. The image stays small; the full original remains on
/// disk only for explicitly opening Quick Look. No input or clipboard services.
@MainActor final class ScreenshotThumbnailView: NSView {
    private let onHover: (Bool) -> Void
    private var hoverArea: NSTrackingArea?

    init(image: NSImage, target: AnyObject?, openAction: Selector?, closeAction: Selector?,
         onHover: @escaping (Bool) -> Void = { _ in }) {
        self.onHover = onHover
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 220))
        let content = NSView(frame: bounds)
        content.autoresizingMask = [.width, .height]
        // Shared native glass/frosted material; screenshot delivery stays unchanged.
        addSubview(BridgeGlassPanelView(frame: bounds, content: content, cornerRadius: 22))

        let imageButton = NSButton(image: image, target: target, action: openAction)
        imageButton.isBordered = false; imageButton.imageScaling = .scaleProportionallyUpOrDown
        imageButton.frame = NSRect(x: 12, y: 36, width: 296, height: 172)
        imageButton.wantsLayer = true
        imageButton.layer?.cornerRadius = 12; imageButton.layer?.masksToBounds = true
        imageButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        imageButton.setAccessibilityLabel("開啟截圖快速查看")
        imageButton.toolTip = "點擊放大查看截圖"; content.addSubview(imageButton)

        let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage()
        let success = NSImageView(image: symbol)
        success.frame = NSRect(x: 14, y: 12, width: 13, height: 13)
        success.contentTintColor = .systemGreen; success.setAccessibilityElement(false)
        content.addSubview(success)
        let title = NSTextField(labelWithString: "已複製")
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .labelColor; title.frame = NSRect(x: 33, y: 11, width: 46, height: 15)
        content.addSubview(title)
        let hint = NSTextField(labelWithString: "可貼上 · 點圖放大")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 86, y: 11, width: 178, height: 15)
        content.addSubview(hint)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "關閉截圖縮圖") ?? NSImage(),
            target: target, action: closeAction)
        close.isBordered = false; close.contentTintColor = .secondaryLabelColor
        close.frame = NSRect(x: 278, y: 5, width: 26, height: 26)
        close.setAccessibilityLabel("關閉截圖縮圖"); close.toolTip = "關閉預覽，圖片仍在剪貼簿"
        content.addSubview(close)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    required init?(coder: NSCoder) { nil }
}
