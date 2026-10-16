import AppKit
import SwiftUI
import BridgeCore
import BridgePlatform

/// Explicit, offscreen developer check with generated values only. Does not
/// create a BridgeController, start input, request permissions or show windows.
@MainActor enum FeatureVisualCheck {
    static func handle(_ arguments: [String]) -> Bool {
        guard arguments.first == "--render-feature-checks" else { return false }
        guard arguments.count == 2 else { exit(64) }
        do {
            let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            NSApplication.shared.setActivationPolicy(.prohibited)
            let applications = [ApplicationContext(processID: 1, bundleID: "com.apple.Terminal", displayName: "Terminal", mode: .terminal),
                .init(processID: 2, bundleID: "com.apple.finder", displayName: "Finder", mode: .macOS),
                .init(processID: 3, bundleID: "test.remote", displayName: "遠端 Windows", mode: .remoteWindows)]
            let source = RemoteSourceStatus(identity: "generated-source", displayName: "Chrome Remote Desktop",
                processID: 42, session: 1, transport: .googleRemoteDesktop, confidence: .known,
                semantics: .automatic, observedInput: true, learned: false)
            var calibration = RemoteCalibrationStatus()
            calibration.phase = .review; calibration.targetName = source.displayName
            calibration.targetIdentity = source.identity; calibration.deadline = ProcessInfo.processInfo.systemUptime + 60
            calibration.candidate = .windows; calibration.notice = "已辨識：原始 Windows 按鍵。請確認後套用；確認前設定不變。"
            var screenshot = ScreenshotStatus(); screenshot.lastResult = "尚未擷取文字"
            try render(AnyView(ShortcutPreviewView(settings: BridgeSettings(), applications: applications)),
                       to: output.appendingPathComponent("shortcut-rules.png"), size: NSSize(width: 840, height: 900))
            try render(AnyView(ShortcutPreviewView(settings: BridgeSettings(), applications: applications)),
                       to: output.appendingPathComponent("shortcut-rules-minimum.png"), size: NSSize(width: 730, height: 600))
            try render(AnyView(RemoteCalibrationView(sources: [source], status: calibration, canCalibrate: true, preferenceNotice: nil)),
                       to: output.appendingPathComponent("remote-calibration.png"), size: NSSize(width: 840, height: 740))
            try render(AnyView(Form { ScreenshotTextCaptureSection(status: screenshot, canCapture: true, featuresEnabled: true) }.formStyle(.grouped)),
                       to: output.appendingPathComponent("screenshot-text.png"), size: NSSize(width: 730, height: 400))
            screenshot.isBusy = true; screenshot.recognizingText = true; screenshot.lastResult = "正在本機辨識文字…"
            try render(AnyView(Form { ScreenshotTextCaptureSection(status: screenshot, canCapture: false, featuresEnabled: true) }.formStyle(.grouped)),
                       to: output.appendingPathComponent("screenshot-text-busy.png"), size: NSSize(width: 730, height: 400))
            let sample = NSImage(size: NSSize(width: 480, height: 280), flipped: false) { rect in
                NSColor.systemBlue.setFill(); rect.fill()
                ("WindowsMacBridge\nScreenshot Preview" as NSString).draw(at: NSPoint(x: 24, y: 110),
                    withAttributes: [.font:NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor:NSColor.white])
                return true
            }
            let thumbnail = ScreenshotThumbnailView(image: sample, target: nil, openAction: nil, closeAction: nil)
            try renderView(thumbnail, to: output.appendingPathComponent("screenshot-thumbnail.png"))
            print("Rendered 6 generated feature checks; no controller, capture, clipboard or input services started.")
        } catch { print("Feature layout verification failed: \(error)"); exit(1) }
        return true
    }
    private static func render(_ content: AnyView, to url: URL, size: NSSize) throws {
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        try renderView(host, to: url)
    }
    private static func renderView(_ host: NSView, to url: URL) throws {
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url, options: .withoutOverwriting)
        window.contentView = nil; window.close()
    }
}
