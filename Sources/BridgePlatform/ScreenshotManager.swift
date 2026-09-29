import AppKit
import ApplicationServices
import Carbon
import Foundation
import ImageIO
import BridgeCore

private struct TapResult: @unchecked Sendable {
    let event: Unmanaged<CGEvent>?
}

public enum ScreenshotClipboardResult: Equatable, Sendable {
    case success, unreadableImage, writeFailed
}

public struct ScreenshotImagePayload: Sendable {
    let png: Data
}

public enum ScreenshotImagePreparation {
    /// Local image/bitmap objects never cross threads. Only immutable image data
    /// leaves the pool; AppKit UI and Clipboard remain on the main actor.
    public static func prepare(at url: URL) -> ScreenshotImagePayload? {
        autoreleasepool {
            if url.pathExtension.lowercased() == "pdf" {
                return preparePDF(at: url)
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
            if url.pathExtension.lowercased() == "png",
               let original = try? Data(contentsOf: url, options: .mappedIfSafe),
               original.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
                return ScreenshotImagePayload(png: original)
            }
            guard let encoded = CFDataCreateMutable(kCFAllocatorDefault, 0),
                  let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return ScreenshotImagePayload(png: encoded as Data)
        }
    }

    private static func preparePDF(at url: URL) -> ScreenshotImagePayload? {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return nil }
        let bounds = page.getBoxRect(.mediaBox).standardized
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              (bounds.width * bounds.height).isFinite else { return nil }
        // PDF is an uncommon screenshot format. Bound its bitmap so a malformed
        // or enormous document cannot cause an unbounded allocation.
        let scale = min(1, 8_192 / max(bounds.width, bounds.height),
                        sqrt(32_000_000 / (bounds.width * bounds.height)))
        let width = max(1, Int(ceil(bounds.width * scale)))
        let height = max(1, Int(ceil(bounds.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.concatenate(page.getDrawingTransform(.mediaBox,
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage(),
              let encoded = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ScreenshotImagePayload(png: encoded as Data)
    }
}

@MainActor public enum ScreenshotClipboard {
    public static func copyImage(at url: URL, to pasteboard: NSPasteboard) -> ScreenshotClipboardResult {
        guard let payload = ScreenshotImagePreparation.prepare(at: url) else { return .unreadableImage }
        return write(payload, to: pasteboard)
    }
    public static func write(_ payload: ScreenshotImagePayload, to pasteboard: NSPasteboard) -> ScreenshotClipboardResult {
        let item = NSPasteboardItem()
        guard item.setData(payload.png, forType: NSPasteboard.PasteboardType("public.png")) else { return .writeFailed }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item]) ? .success : .writeFailed
    }
}

public struct ScreenshotStatus: Equatable, Sendable {
    public var tapActive = false
    public var issue: String?
    public var lastResult = "尚未啟用"
    public var lastCheck: Date?
    public init() {}
}

/// Main-run-loop event tap for the one screenshot shortcut. File and pasteboard
/// work runs after the callback; no screen contents or ordinary keys are logged.
@MainActor public final class ScreenshotManager {
    public var onChange: ((ScreenshotStatus) -> Void)?
    public var onPeriodicCheck: (() -> Void)?
    public private(set) var status = ScreenshotStatus()
    public var logPath: String { logURL.path }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let logURL: URL
    private let lastCheckKey = "screenshot.lastCheck.v1"
    private var enabled = false
    private var captureAllowed = false
    private var accessibilityTrusted = false
    private var shortcut = ScreenshotShortcut()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var checkTimer: Timer?
    private var capture = ScreenshotCaptureLifecycle()
    private var recovery = RecoveryPolicy()
    private var tapGeneration: UInt64 = 0
    private var recoveryQueued: UInt64?

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        // Initialize the shared marker outside the native event callback.
        _ = EventRewriter.generatedEventMarker
        self.defaults = defaults
        self.fileManager = fileManager
        logURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowsMacBridge/Screenshot.log")
    }

    public func start(enabled: Bool) {
        self.enabled = enabled
        capture.configure(enabled: enabled)
        guard enabled else { return }
        verifyAndRepair(reason: "App 啟動")
        if defaults.object(forKey: lastCheckKey) == nil { defaults.set(Date(), forKey: lastCheckKey) }
        scheduleNextCheck()
    }

    public func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        capture.configure(enabled: value)
        recovery.reset()
        if value {
            verifyAndRepair(reason: "功能啟用")
            defaults.set(Date(), forKey: lastCheckKey)
            scheduleNextCheck()
        } else {
            checkTimer?.invalidate(); checkTimer = nil
            destroyTap()
            shortcut.reset()
            setStatus(issue: nil, result: "已關閉；macOS 原始快捷鍵直接通過")
            log("功能關閉，事件攔截已移除")
        }
    }

    public func setWindowsKeyModifier(_ value: WindowsKeyModifier) {
        guard shortcut.windowsKeyModifier != value else { return }
        shortcut.reset()
        shortcut.windowsKeyModifier = value
        if enabled { verifyAndRepair(reason: "Windows 鍵映射已變更") }
    }

    public func setContextMode(_ value: ApplicationMode, ownAppForeground: Bool = false) {
        captureAllowed = value == .macOS || ownAppForeground
    }

    public func stop() {
        checkTimer?.invalidate(); checkTimer = nil
        destroyTap()
        shortcut.reset()
        enabled = false
        capture.configure(enabled: false)
        recovery.reset()
        accessibilityTrusted = false
    }

    public func verifyAndRepair(reason: String) {
        recovery.reset()
        performVerification(reason: reason)
    }

    private func performVerification(reason: String) {
        guard enabled else { return }
        status.lastCheck = Date()
        accessibilityTrusted = AXIsProcessTrusted()
        guard fileManager.isExecutableFile(atPath: "/usr/sbin/screencapture") else {
            destroyTap()
            setStatus(issue: "找不到可執行的 macOS 截圖工具。", result: "檢查失敗")
            log("\(reason)：截圖工具不可執行")
            return
        }
        guard fileManager.isWritableFile(atPath: captureDirectory().path) else {
            destroyTap()
            setStatus(issue: "截圖儲存位置不可寫。", result: "檢查失敗")
            log("\(reason)：截圖儲存位置不可寫")
            return
        }
        guard accessibilityTrusted else {
            destroyTap()
            setStatus(issue: "截圖攔截需要輔助使用權限；授權後重新開啟 App 或開關。", result: "檢查失敗")
            log("\(reason)：輔助使用權限不可用")
            return
        }
        if let tap, (!CFMachPortIsValid(tap) || !CGEvent.tapIsEnabled(tap: tap)) {
            destroyTap()
            log("\(reason)：事件攔截已停用，重新建立")
        }
        if tap == nil { createTap() }
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            let modifier = shortcut.windowsKeyModifier == .option ? "⌥" : "⌘"
            setStatus(issue: nil, result: "Shift+Win+S（⇧\(modifier)S）攔截正常")
            log("\(reason)：⇧\(modifier)S 攔截正常")
        } else {
            setStatus(issue: "無法建立截圖 Event Tap；請檢查輔助使用權限。", result: "檢查失敗")
            log("\(reason)：無法建立截圖 Event Tap")
        }
    }

    private func scheduleNextCheck() {
        checkTimer?.invalidate()
        guard enabled else { return }
        let delay = ScreenshotCheckSchedule.delay(lastCheck: defaults.object(forKey: lastCheckKey) as? Date,
                                                  now: Date())
        checkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.enabled else { return }
                self.verifyAndRepair(reason: "30 天定期檢查")
                self.onPeriodicCheck?()
                self.defaults.set(Date(), forKey: self.lastCheckKey)
                self.status.lastCheck = Date()
                self.onChange?(self.status)
                self.scheduleNextCheck()
            }
        }
        checkTimer?.tolerance = min(60, delay * 0.01)
    }

    public func reportConfigurationIssue(_ message: String) {
        guard enabled else { return }
        setStatus(issue: message, result: "配置需要處理")
        log("配置異常：\(message)")
    }

    public func recordRepair(_ message: String) {
        guard enabled else { return }
        log("已修復：\(message)")
    }

    private func createTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<ScreenshotManager>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated { TapResult(event: manager.handle(type, event: event)) }.event
        }
        // Before the Windows translation tap (.tailAppendEventTap), independently
        // of startup, toggle and recovery order. No privileged HID event tap.
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else { return }
        tapGeneration &+= 1
        tap = newTap; source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        status.tapActive = CGEvent.tapIsEnabled(tap: newTap)
    }

    private func destroyTap() {
        tapGeneration &+= 1
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        status.tapActive = false
        shortcut.reset()
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            shortcut.reset()
            let generation = tapGeneration
            if recoveryQueued != generation {
                recoveryQueued = generation
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.recoveryQueued == generation { self.recoveryQueued = nil }
                    // A delayed failure from an old tap must not destroy a new
                    // tap after a toggle, permission repair or session change.
                    guard self.enabled, self.tapGeneration == generation else { return }
                    if self.recovery.mayRetry(at: ProcessInfo.processInfo.systemUptime) {
                        self.performVerification(reason: "Event Tap 停用")
                    } else {
                        self.destroyTap()
                        self.setStatus(issue: "截圖攔截反覆停用，已停止自動重試；請放開按鍵後重新開啟截圖開關。", result: "自動恢復已暫停")
                        self.log("Event Tap 60 秒內反覆停用，停止自動重試")
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard enabled, type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
        let key = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard key == ScreenshotShortcut.keyCode else { return Unmanaged.passUnretained(event) }
        let decision = shortcut.handle(type: type, event: event, allowsCapture: captureAllowed)
        switch decision {
        case .passThrough: return Unmanaged.passUnretained(event)
        case .suppress: return nil
        case .capture:
            if IsSecureEventInputEnabled() || !accessibilityTrusted {
                shortcut.reset()
                return Unmanaged.passUnretained(event)
            }
            if let token = capture.begin() {
                DispatchQueue.main.async { [weak self] in self?.beginCapture(token) }
            }
            return nil
        }
    }

    private func beginCapture(_ token: ScreenshotCaptureLifecycle.Token) {
        guard capture.isCurrent(token) else { _ = capture.complete(token); return }
        let destination = captureURL()
        setStatus(issue: nil, result: "正在框選截圖")
        log("快捷鍵已接收，開始框選截圖")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-t", destination.pathExtension, destination.path]
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor [weak self] in await self?.finishCapture(exitCode: code, url: destination, token: token) }
        }
        do {
            try process.run()
        } catch {
            guard capture.complete(token) else { return }
            setStatus(issue: "無法啟動 macOS 截圖工具：\(error.localizedDescription)", result: "截圖失敗")
            log("截圖工具啟動失敗：\(error.localizedDescription)")
        }
    }

    private func finishCapture(exitCode: Int32, url: URL, token: ScreenshotCaptureLifecycle.Token) async {
        guard capture.isCurrent(token) else { _ = capture.complete(token); return }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.intValue > 0 else {
            guard capture.complete(token) else { return }
            if exitCode != 0 { log("截圖已取消或失敗，結束碼 \(exitCode)") }
            setStatus(issue: nil, result: "截圖已取消")
            return
        }
        if exitCode != 0 { log("截圖工具結束碼 \(exitCode)，但已產生圖片；繼續複製") }
        let payload = await Task.detached(priority: .userInitiated) {
            ScreenshotImagePreparation.prepare(at: url)
        }.value
        // Off/on while decoding or while the native selection UI is open must
        // not let the previous capture overwrite Clipboard or status.
        guard capture.complete(token) else { return }
        let result = payload.map { ScreenshotClipboard.write($0, to: .general) } ?? .unreadableImage
        switch result {
        case .unreadableImage:
            setStatus(issue: "圖片已儲存，但無法讀取以複製到剪貼簿。", result: "儲存成功、複製失敗")
            log("圖片已儲存，但無法讀取：\(url.path)")
            return
        case .writeFailed:
            setStatus(issue: "圖片已儲存，但無法寫入剪貼簿。", result: "儲存成功、複製失敗")
            log("圖片已儲存，但剪貼簿寫入失敗：\(url.path)")
            return
        case .success: break
        }
        setStatus(issue: nil, result: "截圖已儲存並複製，可直接按 ⌘V")
        log("截圖已儲存並複製：\(url.path)")
    }

    private func captureURL() -> URL {
        let preferences = UserDefaults(suiteName: "com.apple.screencapture")
        let directory = captureDirectory()
        let preferredType = preferences?.string(forKey: "type")?.lowercased() ?? "png"
        let format = preferredType == "jpeg" ? "jpg"
            : (["png", "jpg", "tiff", "pdf"].contains(preferredType) ? preferredType : "png")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).\(format)"
        return directory.appendingPathComponent(name)
    }

    private func captureDirectory() -> URL {
        let preferences = UserDefaults(suiteName: "com.apple.screencapture")
        let configuredLocation = preferences?.string(forKey: "location")
        let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let requested = configuredLocation.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? desktop
        return fileManager.isWritableFile(atPath: requested.path) ? requested : desktop
    }

    private func setStatus(issue: String?, result: String) {
        status.issue = issue
        status.lastResult = result
        status.tapActive = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        onChange?(status)
    }

    private func log(_ message: String) {
        do {
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bytes = (try? fileManager.attributesOfItem(atPath: logURL.path)[.size]) as? NSNumber,
               bytes.intValue >= 512 * 1024 {
                let previous = logURL.appendingPathExtension("1")
                try? fileManager.removeItem(at: previous)
                try fileManager.moveItem(at: logURL, to: previous)
            }
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
            let data = Data(line.utf8)
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else { try data.write(to: logURL, options: .atomic) }
        } catch {
            NSLog("WindowsMacBridge screenshot diagnostic logging failed: %@", error.localizedDescription)
        }
    }
}
