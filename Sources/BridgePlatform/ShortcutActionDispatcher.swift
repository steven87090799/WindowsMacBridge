import AppKit
import ApplicationServices
import Carbon
import BridgeCore

/// A bounded mailbox separates the keyboard callback from AppKit, AX and pasteboard work.
/// No clipboard payload or AX text/value attribute is read.
public final class ShortcutActionDispatcher: @unchecked Sendable {
    private struct Request: Sendable {
        let action: ShortcutAction
        let context: ApplicationContext
        let generation: UInt64
        let deadline: Double
    }
    private let lock = NSLock()
    private var pending = [Request?](repeating: nil, count: 16)
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var scheduled = false
    private var generation: UInt64 = 0
    private var context = ApplicationContext()
    private var enabled = false
    private var finderEnabled = false
    private var epoch: UInt64 = 0
    private var message = ""
    private let marker: Int64
    @MainActor private var cut = FinderCutState()
    @MainActor private var cutGeneration: UInt64 = .max

    public init(marker: Int64) { self.marker = marker }

    /// UI/lifecycle path only. Synchronously invalidates queued work before a pause returns.
    public func cancelPending(disable: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        if disable { enabled = false }
    }

    @discardableResult public func update(context: ApplicationContext, enabled: Bool,
                                         finderEnabled: Bool = false, epoch: UInt64 = 0) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        if self.context != context || self.enabled != enabled || self.finderEnabled != finderEnabled || self.epoch != epoch {
            generation &+= 1
            self.context = context; self.enabled = enabled
            self.finderEnabled = finderEnabled; self.epoch = epoch
        }
        return true
    }
    public func status() -> String {
        lock.lock(); defer { lock.unlock() }
        return message
    }
    /// try-lock only on the callback; on contention or overflow the request is dropped.
    @discardableResult public func submit(_ action: ShortcutAction, context expected: ApplicationContext) -> Bool {
        guard lock.try() else { return false }
        guard enabled, context == expected, count < pending.count else { lock.unlock(); return false }
        if case .finder = action, !finderEnabled { lock.unlock(); return false }
        pending[writeIndex] = Request(action: action, context: context, generation: generation,
                                     deadline: ProcessInfo.processInfo.systemUptime + 0.6)
        writeIndex = (writeIndex + 1) % pending.count; count += 1
        let start = !scheduled; scheduled = true
        lock.unlock()
        if start { Task { @MainActor [self] in await drain() } }
        return true
    }
    private func pop() -> Request? {
        lock.lock(); defer { lock.unlock() }
        guard count > 0 else { scheduled = false; return nil }
        let request = pending[readIndex]; pending[readIndex] = nil
        readIndex = (readIndex + 1) % pending.count; count -= 1
        return request
    }
    private func isCurrent(_ request: Request) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && generation == request.generation &&
            ProcessInfo.processInfo.systemUptime < request.deadline
    }
    private func report(_ value: String) {
        lock.lock(); message = value; lock.unlock()
    }
    @MainActor private func allowed(_ request: Request) -> Bool {
        isCurrent(request) && AXIsProcessTrusted() && CGPreflightPostEventAccess() &&
            !IsSecureEventInputEnabled() &&
            NSWorkspace.shared.frontmostApplication?.processIdentifier == request.context.processID
    }
    @MainActor private func drain() async {
        while let request = pop() {
            guard allowed(request) else { cut.cancel(); continue }
            if cutGeneration != request.generation { cut.cancel(); cutGeneration = request.generation }
            switch request.action {
            case .system(let action):
                let bundle = action == .openFinder ? "com.apple.finder" : "com.apple.ActivityMonitor"
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                    do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                    catch { report("系統 App 開啟失敗。") }
                } else { report("找不到要求開啟的系統 App。") }
            case .finder(let action): await performFinder(action, request: request)
            }
        }
    }

    @MainActor private func performFinder(_ action: FinderAction, request: Request) async {
        guard request.context.bundleID == "com.apple.finder" else { return }
        let pid = request.context.processID
        let focus = await Task.detached(priority: .userInitiated) { FinderFocusReader.read(pid: pid) }.value
        guard allowed(request) else { cut.cancel(); return }
        let pasteboard = NSPasteboard.general
        let now = ProcessInfo.processInfo.systemUptime
        switch action {
        case .copy, .cut:
            cut.cancel()
            let before = pasteboard.changeCount
            // Text cut stays text cut; unknown focus never arms a file move.
            let key: UInt16 = action == .cut && focus != .files ? 7 : 8
            guard emit(key, .command, request: request) else { return }
            guard action == .cut && focus == .files else { return }
            // Copy acknowledgement is bounded and metadata-only. Do not guess on multiple changes.
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(20))
                guard allowed(request) else { cut.cancel(); return }
                let changed = pasteboard.changeCount
                if changed != before {
                    guard changed == before + 1, pasteboard.types?.contains(.fileURL) == true else {
                        report("Finder 剪下未建立：剪貼簿來源無法確認。"); return
                    }
                    cut.arm(changeCount: changed, finderPID: pid, now: ProcessInfo.processInfo.systemUptime)
                    report("Finder 檔案已複製，等待移動貼上（5 分鐘內有效）。")
                    return
                }
            }
            report("Finder 複製逾時；沒有保留剪下標記。")
        case .paste:
            let count = pasteboard.changeCount
            let move = focus == .files && pasteboard.types?.contains(.fileURL) == true &&
                cut.consume(changeCount: count, finderPID: pid, now: now)
            cut.cancel()
            guard pasteboard.changeCount == count else { report("剪貼簿已改變，取消本次貼上。"); return }
            if emit(9, move ? [.command, .option] : .command, request: request) {
                report(move ? "已送出 Finder 移動請求；由 Finder 處理確認與結果。" : "已送出 Finder 貼上請求。")
            }
        case .open:
            cut.cancel()
            _ = emit(focus == .files ? 31 : 36, focus == .files ? .command : [], request: request)
        case .rename:
            cut.cancel()
            if focus == .files { _ = emit(36, [], request: request) }
            else { report("F2 改名略過：焦點不是可確認的檔案列表。") }
        case .trash:
            cut.cancel()
            if focus == .files { _ = emit(51, .command, request: request) }
            else { report("刪除略過：焦點不是可確認的檔案列表。") }
        }
    }
    /// Complete key pairs, private source, marker and target PID. No global held modifiers.
    @MainActor private func emit(_ key: UInt16, _ modifiers: Modifiers, request: Request) -> Bool {
        guard allowed(request), let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        for event in [down, up] {
            EventRewriter.apply(to: event, keyCode: key, modifiers: modifiers, marker: marker)
            event.postToPid(request.context.processID)
        }
        return true
    }
}

enum FinderFocus: Sendable { case files, text, unknown }
enum FinderFocusReader {
    /// Runs on a worker. Reads roles/parents only, never selected text or document values.
    static func read(pid: Int32) -> FinderFocus {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        var element = unsafeDowncast(focused, to: AXUIElement.self)
        for _ in 0..<5 {
            AXUIElementSetMessagingTimeout(element, 0.03)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
                  let role = value as? String else { return .unknown }
            if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { return .text }
            if [kAXOutlineRole, kAXTableRole, kAXBrowserRole].contains(role) { return .files }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return .unknown }
            element = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return .unknown
    }
}
