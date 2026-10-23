import AppKit
import SwiftUI
import BridgeCore
import BridgePlatform
import InputSourceSupport

/// Explicit, offscreen developer check with generated values only. Does not
/// create a BridgeController, start input, request permissions or show windows.
@MainActor enum FeatureVisualCheck {
    /// Visible click/focus check, using generated pixels and no input engine,
    /// capture, permissions or clipboard writes. Invoked only by this argument.
    static func handlePreview(_ arguments: [String]) -> Bool {
        guard arguments.first == "--screenshot-preview-fixture" else { return false }
        guard arguments.count == 2 else { exit(64) }
        do {
            let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            NSApplication.shared.setActivationPolicy(.accessory)
            let image = generatedScreenshot(size: NSSize(width: 1200, height: 700))
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]),
                  let thumbnail = ScreenshotPreviewPreparation.thumbnail(png: png) else { exit(1) }
            let source = output.appendingPathComponent("generated-preview.png")
            try png.write(to: source, options: .withoutOverwriting)
            let presenter = ScreenshotThumbnailPresenter(expirationDelay: 60)
            guard presenter.present(.init(thumbnailPNG: thumbnail, sourceURL: source, ownsSourceFile: false)) else { exit(1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { NSApp.stop(nil) }
            withExtendedLifetime(presenter) { NSApp.run() }
            presenter.dismiss()
        } catch { print("Screenshot preview fixture failed: \(error)"); exit(1) }
        return true
    }
    static func handle(_ arguments: [String]) -> Bool {
        guard arguments.first == "--render-feature-checks" else { return false }
        guard arguments.count == 2 else { exit(64) }
        do {
            let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            NSApplication.shared.setActivationPolicy(.prohibited)
            for page in SettingsPage.allCases {
                guard NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) != nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
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
            for dark in [false, true] {
                let sample = generatedScreenshot(size: NSSize(width: 720, height: 420))
                let thumbnail = ScreenshotThumbnailView(image: sample, target: nil, openAction: nil, closeAction: nil)
                thumbnail.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                try renderView(thumbnail, to: output.appendingPathComponent(dark ? "screenshot-thumbnail-dark.png" : "screenshot-thumbnail-light.png"))
            }
            let portrait = ScreenshotThumbnailView(image: generatedScreenshot(size: NSSize(width: 360, height: 720)),
                target: nil, openAction: nil, closeAction: nil)
            try renderView(portrait, to: output.appendingPathComponent("screenshot-thumbnail-portrait.png"))
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                let metrics = PerformanceReading(uptime: 12, processCPUSeconds: 0.404, cpuTicks: [120, 30, 150, 0],
                    physicalMemory: 16 << 30, activeMemory: 5 << 30, wiredMemory: 2 << 30,
                    compressedMemory: 1 << 30, processFootprint: 72 << 20)
                let previous = PerformanceReading(uptime: 10, processCPUSeconds: 0.4, cpuTicks: [100, 20, 80, 0],
                    physicalMemory: 16 << 30, activeMemory: 5 << 30, wiredMemory: 2 << 30,
                    compressedMemory: 1 << 30, processFootprint: 72 << 20)
                let performance = GlassSettingsChrome(selection: .constant(.performance), advanced: false,
                    isOperating: true, status: "Generated fixture", version: "fixture") {
                    PerformanceReadout(snapshot: PerformanceSnapshot(current: metrics, previous: previous))
                }
                try render(AnyView(performance), to: output.appendingPathComponent("performance-\(mode).png"),
                           size: NSSize(width: 1040, height: 780), dark: dark)
                var selected = InputSourceStatus()
                selected.summary = "● 唯音繁體已選擇"; selected.selectionConfirmed = true
                let input = GlassSettingsChrome(selection: .constant(.inputSources), advanced: false,
                    isOperating: true, status: "Generated fixture", version: "fixture") {
                    Form { Section("唯音繁體／ABC") { InputSourceStatusLabel(status: selected) } }
                        .formStyle(.grouped).scrollContentBackground(.hidden)
                }
                try render(AnyView(input), to: output.appendingPathComponent("input-source-status-\(mode).png"),
                           size: NSSize(width: 1040, height: 780), dark: dark)
                let rules = GlassSettingsChrome(selection: .constant(.preview), advanced: true,
                    isOperating: true, status: "Windows 快捷鍵已啟用", version: AppBuildInfo.current.versionLabel) {
                    ShortcutPreviewView(settings: BridgeSettings(), applications: applications)
                }
                try render(AnyView(rules), to: output.appendingPathComponent("glass-settings-\(mode).png"),
                           size: NSSize(width: 1040, height: 780), dark: dark)
                let remote = GlassSettingsChrome(selection: .constant(.remoteCalibration), advanced: false,
                    isOperating: false, status: "請確認鍵盤權限", version: AppBuildInfo.current.versionLabel) {
                    RemoteCalibrationView(sources: [source], status: calibration, canCalibrate: true, preferenceNotice: nil)
                }
                try render(AnyView(remote), to: output.appendingPathComponent("glass-calibration-\(mode).png"),
                           size: NSSize(width: 1040, height: 780), dark: dark)
            }
            let compact = GlassSettingsChrome(selection: .constant(.preview), advanced: false,
                isOperating: true, status: "Windows 快捷鍵已啟用", version: AppBuildInfo.current.versionLabel) {
                ShortcutPreviewView(settings: BridgeSettings(), applications: applications)
            }
            try render(AnyView(compact), to: output.appendingPathComponent("glass-settings-minimum.png"),
                       size: NSSize(width: 730, height: 600))
            try render(AnyView(compact), to: output.appendingPathComponent("glass-settings-high-contrast.png"),
                       size: NSSize(width: 1040, height: 780), highContrast: true)
            for dark in [false, true] {
                let textCapture = GlassSettingsChrome(selection: .constant(.general), advanced: false,
                    isOperating: true, status: "Windows 快捷鍵已啟用", version: AppBuildInfo.current.versionLabel) {
                    Form { ScreenshotTextCaptureSection(status: screenshot, canCapture: false, featuresEnabled: true) }
                        .formStyle(.grouped).scrollContentBackground(.hidden)
                }
                try render(AnyView(textCapture), to: output.appendingPathComponent(dark ? "glass-text-dark.png" : "glass-text-light.png"),
                           size: NSSize(width: 1040, height: 780), dark: dark)
            }
            print("Rendered 20 generated feature checks; no controller, capture, clipboard or input services started.")
        } catch { print("Feature layout verification failed: \(error)"); exit(1) }
        return true
    }
    private static func generatedScreenshot(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.24, blue: 0.58, alpha: 1),
                       ending: NSColor(srgbRed: 0.35, green: 0.65, blue: 0.76, alpha: 1))?.draw(in: rect, angle: 35)
            let inset = rect.insetBy(dx: 28, dy: 28)
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: inset, xRadius: 20, yRadius: 20).fill()
            ("WindowsMacBridge" as NSString).draw(at: NSPoint(x: 48, y: rect.midY + 12),
                withAttributes: [.font: NSFont.systemFont(ofSize: size.width < 500 ? 22 : 34, weight: .semibold), .foregroundColor: NSColor.white])
            ("Screenshot preview" as NSString).draw(at: NSPoint(x: 48, y: rect.midY - 24),
                withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
            return true
        }
    }

    private static func render(_ content: AnyView, to url: URL, size: NSSize, dark: Bool = false, highContrast: Bool = false) throws {
        let appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastAqua : (dark ? .darkAqua : .aqua))!
        var renderedWindow: NSWindow?
        // Native symbol images can be cached when a hidden host is first created.
        // Supply the same drawing appearance during creation and rasterization.
        appearance.performAsCurrentDrawingAppearance {
            let window = SettingsWindowFactory.make(content: content.environment(\.colorScheme, dark ? .dark : .light))
            window.appearance = appearance
            renderedWindow = window
        }
        guard let window = renderedWindow else { throw CocoaError(.fileWriteUnknown) }
        window.setContentSize(size)
        for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard let host = window.contentView?.superview else { throw CocoaError(.fileWriteUnknown) }
        host.layoutSubtreeIfNeeded()
        try writePNG(host, to: url)
        print("Native layout: \(url.lastPathComponent), toolbar=\(window.toolbar != nil)")
        window.contentViewController = nil; window.close()
    }
    private static func renderView(_ host: NSView, to url: URL) throws {
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()
        try writePNG(host, to: url)
        window.contentView = nil; window.close()
    }
    private static func writePNG(_ host: NSView, to url: URL) throws {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url, options: .withoutOverwriting)
    }
}
