import AppKit
import ApplicationServices
import Carbon
import Foundation

private struct TapResult: @unchecked Sendable {
    let event: Unmanaged<CGEvent>?
}

public enum ScreenshotClipboardResult: Equatable, Sendable {
    case success, unreadableImage, writeFailed
}

@MainActor public enum ScreenshotClipboard {
    public static func copyImage(at url: URL, to pasteboard: NSPasteboard) -> ScreenshotClipboardResult {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return .unreadableImage
        }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: NSPasteboard.PasteboardType("public.png")),
              item.setData(tiff, forType: .tiff) else { return .writeFailed }
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
    private var shortcut = ScreenshotShortcut()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var checkTimer: Timer?
    private var captureInProgress = false

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        logURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowsMacBridge/Screenshot.log")
    }

    public func start(enabled: Bool) {
        self.enabled = enabled
        guard enabled else { return }
        verifyAndRepair(reason: "App 啟動")
        if defaults.object(forKey: lastCheckKey) == nil { defaults.set(Date(), forKey: lastCheckKey) }
        scheduleNextCheck()
    }

    public func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
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

    public func stop() {
        checkTimer?.invalidate(); checkTimer = nil
        destroyTap()
        shortcut.reset()
        enabled = false
    }

    public func verifyAndRepair(reason: String) {
        guard enabled else { return }
        status.lastCheck = Date()
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
        guard AXIsProcessTrusted() else {
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
            setStatus(issue: nil, result: "設定與快捷鍵攔截正常")
            log("\(reason)：設定與快捷鍵攔截正常")
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
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else { return }
        tap = newTap; source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        status.tapActive = CGEvent.tapIsEnabled(tap: newTap)
    }

    private func destroyTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        status.tapActive = false
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            shortcut.reset()
            DispatchQueue.main.async { [weak self] in self?.verifyAndRepair(reason: "Event Tap 停用") }
            return Unmanaged.passUnretained(event)
        }
        guard enabled, type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
        let key = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard key == ScreenshotShortcut.keyCode else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let decision = shortcut.handle(keyCode: key, isDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            command: flags.contains(.maskCommand), shift: flags.contains(.maskShift),
            option: flags.contains(.maskAlternate), control: flags.contains(.maskControl))
        switch decision {
        case .passThrough: return Unmanaged.passUnretained(event)
        case .suppress: return nil
        case .capture:
            if IsSecureEventInputEnabled() || !AXIsProcessTrusted() {
                shortcut.reset()
                return Unmanaged.passUnretained(event)
            }
            if !captureInProgress {
                captureInProgress = true
                DispatchQueue.main.async { [weak self] in self?.beginCapture() }
            }
            return nil
        }
    }

    private func beginCapture() {
        guard enabled else { captureInProgress = false; return }
        let destination = captureURL()
        setStatus(issue: nil, result: "正在框選截圖")
        log("快捷鍵已接收，開始框選截圖")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-t", destination.pathExtension, destination.path]
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor [weak self] in self?.finishCapture(exitCode: code, url: destination) }
        }
        do {
            try process.run()
        } catch {
            captureInProgress = false
            setStatus(issue: "無法啟動 macOS 截圖工具：\(error.localizedDescription)", result: "截圖失敗")
            log("截圖工具啟動失敗：\(error.localizedDescription)")
        }
    }

    private func finishCapture(exitCode: Int32, url: URL) {
        captureInProgress = false
        guard enabled else { return }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.intValue > 0 else {
            if exitCode != 0 { log("截圖已取消或失敗，結束碼 \(exitCode)") }
            setStatus(issue: nil, result: "截圖已取消")
            return
        }
        if exitCode != 0 { log("截圖工具結束碼 \(exitCode)，但已產生圖片；繼續複製") }
        switch ScreenshotClipboard.copyImage(at: url, to: .general) {
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
