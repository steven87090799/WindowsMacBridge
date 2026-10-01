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

/// ImageIO writes incrementally. Refuse a chunk before it can grow the encoded
/// buffer beyond its budget; a post-finalize size check alone is too late.
private final class PNGEncodingBuffer {
    let limit: Int
    private(set) var data = Data()
    private(set) var overflow = false
    init(limit: Int) { self.limit = limit; data.reserveCapacity(min(limit, 64 * 1024)) }
    func append(_ pointer: UnsafeRawPointer, count: Int) -> Int {
        guard !overflow, count >= 0, count <= limit - data.count else { overflow = true; return 0 }
        data.append(pointer.assumingMemoryBound(to: UInt8.self), count: count)
        return count
    }
}

public enum ScreenshotImagePreparation {
    static func encodePNG(_ image: CGImage, maximumBytes: Int = ImageMemoryBudget.maximumFileBytes) -> Result<ScreenshotImagePayload, ScreenshotFailure> {
        guard maximumBytes > 0 else { return .failure(.encodeFailure) }
        let buffer = PNGEncodingBuffer(limit: min(maximumBytes, ImageMemoryBudget.maximumFileBytes))
        var callbacks = CGDataConsumerCallbacks(putBytes: { info, bytes, count in
            guard let info else { return 0 }
            return Unmanaged<PNGEncodingBuffer>.fromOpaque(info).takeUnretainedValue().append(bytes, count: count)
        }, releaseConsumer: nil)
        return withExtendedLifetime(buffer) {
            guard let consumer = CGDataConsumer(info: Unmanaged.passUnretained(buffer).toOpaque(), cbks: &callbacks),
                  let destination = CGImageDestinationCreateWithDataConsumer(consumer, "public.png" as CFString, 1, nil) else {
                return .failure(.encodeFailure)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination), !buffer.overflow, !buffer.data.isEmpty else { return .failure(.encodeFailure) }
            return .success(ScreenshotImagePayload(png: buffer.data))
        }
    }
    /// Local image/bitmap objects never cross threads. Only immutable image data
    /// leaves the pool; AppKit UI and Clipboard remain on the main actor.
    public static func prepare(at url: URL) -> ScreenshotImagePayload? {
        try? prepareResult(at: url).get()
    }
    public static func prepareResult(at url: URL) -> Result<ScreenshotImagePayload, ScreenshotFailure> {
        autoreleasepool {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let bytes = (attributes[.size] as? NSNumber)?.intValue,
                  bytes > 0, bytes <= ImageMemoryBudget.maximumFileBytes else { return .failure(.diskFailure) }
            if url.pathExtension.lowercased() == "pdf" {
                return preparePDF(at: url)
            }
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue,
                  (1...64).contains(depth),
                  ImageMemoryBudget.allows(width: width, height: height, bytesPerPixel: 4 * ((depth + 7) / 8)) else {
                return .failure(.decodeFailure)
            }
            if url.pathExtension.lowercased() == "png",
               let original = try? Data(contentsOf: url, options: .mappedIfSafe),
               original.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
                return .success(ScreenshotImagePayload(png: original))
            }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
                  ImageMemoryBudget.allows(width: image.width, height: image.height,
                    bytesPerPixel: max(4, (image.bitsPerPixel + 7) / 8)),
                  image.bytesPerRow <= ImageMemoryBudget.maximumDecodedBytes / image.height else { return .failure(.decodeFailure) }
            return encodePNG(image)
        }
    }

    private static func preparePDF(at url: URL) -> Result<ScreenshotImagePayload, ScreenshotFailure> {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return .failure(.decodeFailure) }
        let bounds = page.getBoxRect(.mediaBox).standardized
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              (bounds.width * bounds.height).isFinite else { return .failure(.decodeFailure) }
        // PDF is an uncommon screenshot format. Bound its bitmap so a malformed
        // or enormous document cannot cause an unbounded allocation.
        guard bounds.width <= Double(ImageMemoryBudget.maximumDimension),
              bounds.height <= Double(ImageMemoryBudget.maximumDimension) else { return .failure(.decodeFailure) }
        let width = max(1, Int(ceil(bounds.width)))
        let height = max(1, Int(ceil(bounds.height)))
        guard ImageMemoryBudget.allows(width: width, height: height, bytesPerPixel: 4) else { return .failure(.decodeFailure) }
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .failure(.decodeFailure) }
        context.concatenate(page.getDrawingTransform(.mediaBox,
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return .failure(.decodeFailure) }
        return encodePNG(image)
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
    private let logger: BoundedDiagnosticLogger
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
    private var runtimePolicy: RuntimePolicySnapshot?
    private var policyEpoch: UInt64 = 0
    private var activeJob: (any ScreenshotCaptureJob)?
    private var sourceJob: SourceWorkToken?
    private var inputRouting = InputRoutingSnapshot()
    private var physicalPreferences: [DeviceInputPreference] = []
    private var jobKind: ScreenshotKind = .region
    private let driver: any ScreenshotCaptureDriving
    private let validatesNativeContext: Bool
    private let captureDirectoryOverride: URL?
    private let authorization: @MainActor () -> Bool
    private let clipboard: NSPasteboard
    private var awaitingNeutral = false
    private var jobTimer: DispatchSourceTimer?
    private var processing: Task<Result<ScreenshotImagePayload, ScreenshotFailure>, Never>?
    private let prepareImage: @Sendable (URL) -> Result<ScreenshotImagePayload, ScreenshotFailure>
    private let captureTimeout: TimeInterval

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default,
                driver: (any ScreenshotCaptureDriving)? = nil, clipboard: NSPasteboard = .general,
                authorization: (@MainActor () -> Bool)? = nil,
                prepareImage: @escaping @Sendable (URL) -> Result<ScreenshotImagePayload, ScreenshotFailure> = ScreenshotImagePreparation.prepareResult,
                captureTimeout: TimeInterval = 120, captureDirectory: URL? = nil) {
        // Initialize the shared marker outside the native event callback.
        _ = EventRewriter.generatedEventMarker
        self.defaults = defaults
        self.fileManager = fileManager
        self.driver = driver ?? NativeScreenshotCaptureDriver()
        self.clipboard = clipboard
        self.validatesNativeContext = authorization == nil
        self.captureDirectoryOverride = captureDirectory
        self.prepareImage = prepareImage
        self.captureTimeout = captureTimeout.isFinite && captureTimeout > 0 ? min(120, captureTimeout) : 120
        self.authorization = authorization ?? { !IsSecureEventInputEnabled() && CGPreflightScreenCaptureAccess() }
        logURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowsMacBridge/Screenshot.log")
        logger = BoundedDiagnosticLogger(url: logURL)
    }

    public func start(enabled: Bool) {
        self.enabled = enabled
        capture.configure(enabled: enabled, epoch: policyEpoch)
        guard enabled else { return }
        verifyAndRepair(reason: "App 啟動")
        if defaults.object(forKey: lastCheckKey) == nil { defaults.set(Date(), forKey: lastCheckKey) }
        scheduleNextCheck()
    }

    public func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        capture.configure(enabled: value, epoch: policyEpoch)
        recovery.reset()
        if value {
            verifyAndRepair(reason: "功能啟用")
            defaults.set(Date(), forKey: lastCheckKey)
            scheduleNextCheck()
        } else {
            activeJob?.cancel(.policyCancelled)
        processing?.cancel(); jobTimer?.cancel(); jobTimer = nil
            checkTimer?.invalidate(); checkTimer = nil
            destroyTap()
            shortcut.reset()
            setStatus(issue: nil, result: "已關閉；macOS 原始快捷鍵直接通過")
            log("功能關閉，事件攔截已移除")
        }
    }

    public func applyRuntimePolicy(_ policy: RuntimePolicySnapshot, windowsKey: WindowsKeyModifier,
                                   printScreen: PrintScreenBehavior) {
        guard runtimePolicy != policy || shortcut.windowsKeyModifier != windowsKey || shortcut.printScreenBehavior != printScreen else { return }
        runtimePolicy = policy; policyEpoch = policy.generation
        activeJob?.cancel(.policyCancelled)
        processing?.cancel(); jobTimer?.cancel(); jobTimer = nil
        capture.configure(enabled: policy.permitsScreenshots, epoch: policyEpoch)
        captureAllowed = policy.permitsScreenshots
        shortcut.windowsKeyModifier = windowsKey; shortcut.printScreenBehavior = printScreen
        setEnabled(policy.permitsScreenshots)
        if enabled && policy.input.backend == .eventTap && tap == nil { performVerification(reason: "執行政策變更") }
        awaitingNeutral = !InputEngine.modifiers(CGEventSource.flagsState(.hidSystemState)).isEmpty
        if policy.input.backend == .deviceHID { destroyTap() }
    }

    /// HID dispatches the physical shortcut through versioned IPC, so its virtual reports
    /// can never be mistaken for an uncaptured keyboard's Alt+Shift+S by a second tap.
    public func applyInputRouting(_ routing: InputRoutingSnapshot) {
        inputRouting = routing
        if sourceJob?.validForAsyncWork == false {
            activeJob?.cancel(.policyCancelled); processing?.cancel(); capture.invalidate()
            sourceJob = nil
        }
    }
    public func applyPhysicalPreferences(_ preferences: [DeviceInputPreference]) {
        guard physicalPreferences != preferences else { return }
        physicalPreferences = Array(preferences.prefix(16))
        // No physical device ID exists at this stage. Conservatively cancel local work;
        // a classified remote job has its own validity token and remains independent.
        if sourceJob == nil && (activeJob != nil || processing != nil) {
            activeJob?.cancel(.policyCancelled); processing?.cancel(); capture.invalidate()
        }
    }
    public func requestCapture(_ kind: ScreenshotKind, source: SourceWorkToken? = nil) {
        guard source?.validForAsyncWork ?? true, enabled, captureAllowed, let token = capture.begin() else { return }
        sourceJob = source
        jobKind = kind
        beginCapture(token, kind: kind)
    }

    public func stop() {
        checkTimer?.invalidate(); checkTimer = nil
        destroyTap()
        shortcut.reset()
        enabled = false
        activeJob?.cancel(.policyCancelled)
        processing?.cancel(); jobTimer?.cancel(); jobTimer = nil
        capture.configure(enabled: false, epoch: policyEpoch)
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
        if runtimePolicy?.input.backend == .deviceHID {
            destroyTap()
            setStatus(issue: nil, result: "HID 實體截圖快捷鍵已啟用")
            return
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
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
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
        guard enabled else { return Unmanaged.passUnretained(event) }
        let evidence = InputOriginEvidence(processID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
                                           stateID: event.getIntegerValueField(.eventSourceStateID), ownEvent: EventRewriter.isGeneratedByBridge(event))
        guard inputRouting.classify(evidence, physicalBackend: runtimePolicy?.input.backend ?? .eventTap) == .physicalFallback else {
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if InputEngine.modifiers(event.flags).isEmpty { awaitingNeutral = false }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
        let key = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        if key == 53 && type == .keyDown && jobKind == .region && !EventRewriter.isGeneratedByBridge(event) {
            activeJob?.noteUserCancellation()
        }
        guard ScreenshotShortcut.supports(key) else { return Unmanaged.passUnretained(event) }
        let physicalAllowed = BackendCapabilities.eventTap.supports(runtimePolicy?.input.deviceScope ?? .allKeyboards, preferences: physicalPreferences)
        let decision = shortcut.handle(type: type, event: event, allowsCapture: captureAllowed && physicalAllowed && !awaitingNeutral)
        switch decision {
        case .passThrough: return Unmanaged.passUnretained(event)
        case .suppress: return nil
        case .capture:
            if IsSecureEventInputEnabled() || !accessibilityTrusted {
                shortcut.reset()
                return Unmanaged.passUnretained(event)
            }
            if let token = capture.begin() {
                sourceJob = nil
                let kind = shortcut.captureKind
                DispatchQueue.main.async { [weak self] in self?.beginCapture(token, kind: kind) }
            }
            return nil
        }
    }

    private func beginCapture(_ token: ScreenshotCaptureLifecycle.Token, kind: ScreenshotKind) {
        guard sourceJob?.validForAsyncWork ?? true, capture.isCurrent(token), isAuthorized() else {
            if capture.complete(token) { setStatus(issue: "螢幕錄製權限不可用。", result: "permissionDenied") }
            return
        }
        let destination = captureURL()
        jobTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + captureTimeout)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.capture.isCurrent(token) else { return }
                self.capture.invalidate()
                self.processing?.cancel(); self.activeJob?.cancel(.timedOut)
                self.setStatus(issue: "截圖工作逾時。", result: "timedOut")
            }
        }
        jobTimer = timer; timer.resume()
        jobKind = kind
        setStatus(issue: nil, result: kind == .region ? "正在框選截圖" : "正在截圖")
        do {
            activeJob = try driver.launch(to: destination, kind: kind,
                processID: runtimePolicy?.input.foreground.processID ?? 0) { [weak self] code, failure in
                Task { @MainActor [weak self] in
                    await self?.finishCapture(exitCode: code, failure: failure, url: destination, token: token)
                }
            }
        } catch {
            jobTimer?.cancel(); jobTimer = nil
            guard capture.complete(token) else { return }
            setStatus(issue: "無法啟動 macOS 截圖工具：\(error.localizedDescription)", result: "processFailure")
            log("截圖工具啟動失敗：\(error.localizedDescription)")
        }
    }

    private func finishCapture(exitCode: Int32, failure: ScreenshotFailure?, url: URL, token: ScreenshotCaptureLifecycle.Token) async {
        activeJob = nil
        guard capture.isCurrent(token), sourceJob?.validForAsyncWork ?? true else {
            jobTimer?.cancel(); jobTimer = nil
            _ = capture.complete(token); return
        }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        if let failure = failure ?? ScreenshotFailure.classify(exitCode: exitCode, hasImage: (size?.intValue ?? 0) > 0,
            permission: isAuthorized(), writable: fileManager.isWritableFile(atPath: url.deletingLastPathComponent().path),
            interactive: jobKind == .region) {
            guard capture.complete(token) else { return }
            jobTimer?.cancel(); jobTimer = nil
            setStatus(issue: failure == .userCancelled ? nil : "截圖失敗：\(failure.rawValue)", result: failure.rawValue)
            return
        }
        let prepare = prepareImage
        let work = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return Result<ScreenshotImagePayload, ScreenshotFailure>.failure(.policyCancelled) }
            let result = prepare(url)
            return Task.isCancelled ? .failure(.policyCancelled) : result
        }
        processing = work
        let payload = await work.value
        processing = nil; jobTimer?.cancel(); jobTimer = nil
        // Off/on while decoding or while the native selection UI is open must
        // not let the previous capture overwrite Clipboard or status.
        guard capture.isCurrent(token), sourceJob?.validForAsyncWork ?? true else { _ = capture.complete(token); return }
        guard isAuthorized() else {
            if capture.complete(token) { setStatus(issue: "螢幕錄製權限不可用。", result: "permissionDenied") }
            return
        }
        guard capture.complete(token) else { return }
        let image: ScreenshotImagePayload
        switch payload {
        case .success(let value): image = value
        case .failure(let failure):
            setStatus(issue: "圖片處理失敗：\(failure.rawValue)", result: failure.rawValue)
            return
        }
        let result = ScreenshotClipboard.write(image, to: clipboard)
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

    private func isAuthorized() -> Bool {
        guard authorization() else { return false }
        guard validatesNativeContext, let policy = runtimePolicy else { return true }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == policy.input.foreground.processID,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session[kCGSessionOnConsoleKey as String] as? Bool) == true &&
            (session[kCGSessionLoginDoneKey as String] as? Bool) == true &&
            (session[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value == getuid()
    }

    private func captureURL() -> URL {
        let directory = captureDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).png"
        return directory.appendingPathComponent(name)
    }

    private func captureDirectory() -> URL {
        if let captureDirectoryOverride { return captureDirectoryOverride }
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
        logger.log(message)
    }
}
