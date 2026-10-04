import AppKit
import ApplicationServices
import Carbon
import BridgeCore

public struct SystemApplicationActivation: Sendable {
    private let action: @MainActor @Sendable () -> Void
    public init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    @MainActor public func activate() { action() }
}
@MainActor public protocol SystemApplicationOpening: Sendable {
    func open(bundleID: String) async throws -> SystemApplicationActivation?
}
@MainActor private final class NativeSystemApplicationOpener: SystemApplicationOpening {
    func open(bundleID: String) async throws -> SystemApplicationActivation? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let config = NSWorkspace.OpenConfiguration()
        // Opening is an OS operation which cannot be withdrawn once submitted. Defer
        // foreground activation until its completion passes the original work gate.
        config.activates = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        return .init { _ = app.activate() }
    }
}

/// A bounded mailbox separates the keyboard callback from AppKit, AX and pasteboard work.
/// No clipboard payload or AX text/value attribute is read.
public final class ShortcutActionDispatcher: @unchecked Sendable {
    private struct Request: Sendable {
        let action: ShortcutAction
        let context: ApplicationContext
        let generation: UInt64
        let localGeneration: UInt64
        let deadline: Double
        let source: SourceWorkToken?
    }
    private let lock = NSLock()
    private var pending = [Request?](repeating: nil, count: 16)
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var scheduled = false
    private var generation: UInt64 = 0
    private var localGeneration: UInt64 = 0
    private var context = ApplicationContext()
    private var enabled = false
    private var finderEnabled = false
    private var finderPermanentDeleteEnabled = false
    private var epoch: UInt64 = 0
    private var message = ""
    private let marker: Int64
    private let authorization: (@MainActor @Sendable (ApplicationContext) -> Bool)?
    private let clock: @Sendable () -> Double
    private let systemOpener: (any SystemApplicationOpening)?
    @MainActor private var cut = FinderCutState()
    private var rejected: UInt64 = 0
    @MainActor public var onScreenshot: (@MainActor @Sendable (ScreenshotKind, SourceWorkToken?) -> Void)?

    public init(marker: Int64, authorization: (@MainActor @Sendable (ApplicationContext) -> Bool)? = nil,
                clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
                systemOpener: (any SystemApplicationOpening)? = nil) {
        self.marker = marker; self.authorization = authorization; self.clock = clock; self.systemOpener = systemOpener
    }

    /// Per-device preferences invalidate local work without revoking a remote source.
    public func cancelLocalPending() {
        lock.lock(); localGeneration &+= 1; lock.unlock()
    }

    /// UI/lifecycle path only. Synchronously invalidates queued work before a pause returns.
    public func cancelPending(disable: Bool = false) {
        lock.lock()
        generation &+= 1
        if disable { enabled = false }
        lock.unlock()
    }

    @discardableResult public func update(context: ApplicationContext, enabled: Bool,
                                         finderEnabled: Bool = false,
                                         finderPermanentDeleteEnabled: Bool = false,
                                         epoch: UInt64 = 0) -> Bool {
        guard lock.try() else { return false }
        if self.context != context || self.enabled != enabled || self.finderEnabled != finderEnabled ||
            self.finderPermanentDeleteEnabled != finderPermanentDeleteEnabled ||
            self.epoch != epoch {
            generation &+= 1
            self.context = context; self.enabled = enabled
            self.finderEnabled = finderEnabled
            self.finderPermanentDeleteEnabled = finderPermanentDeleteEnabled
            self.epoch = epoch
        }
        lock.unlock()
        return true
    }
    public func status() -> String {
        lock.lock(); defer { lock.unlock() }
        return message
    }
    public var rejectedCount: UInt64 { lock.lock(); defer { lock.unlock() }; return rejected }
    var hasPendingWork: Bool { lock.lock(); defer { lock.unlock() }; return scheduled }
    /// try-lock only on the callback; on contention or overflow the request is dropped.
    @discardableResult public func submit(_ action: ShortcutAction, context expected: ApplicationContext, source: SourceWorkToken? = nil) -> Bool {
        guard lock.try() else { return false }
        guard enabled, context == expected, count < pending.count else { rejected &+= 1; lock.unlock(); return false }
        if case .finder = action, !finderEnabled { lock.unlock(); return false }
        let lifetime: Double
        switch action {
        case .window, .system: lifetime = 10 // Native App startup can exceed a keyboard action's 0.6s lifetime.
        default: lifetime = 0.6
        }
        pending[writeIndex] = Request(action: action, context: context, generation: generation,
                                     localGeneration: localGeneration,
                                     deadline: clock() + lifetime, source: source)
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
    private func isCurrent(_ request: Request, ignoreDeadline: Bool = false) -> Bool {
        lock.lock()
        let current = enabled && generation == request.generation &&
            (request.source != nil || localGeneration == request.localGeneration) &&
            (ignoreDeadline || clock() < request.deadline)
        lock.unlock()
        return current && (request.source?.validForAsyncWork ?? true)
    }
    private func report(_ value: String) {
        lock.lock(); message = value; lock.unlock()
    }
    @MainActor private func allowed(_ request: Request, ignoreDeadline: Bool = false) -> Bool {
        guard isCurrent(request, ignoreDeadline: ignoreDeadline) else { return false }
        if let authorization { return authorization(request.context) }
        return AXIsProcessTrusted() && CGPreflightPostEventAccess() &&
            !IsSecureEventInputEnabled() &&
            NSWorkspace.shared.frontmostApplication?.processIdentifier == request.context.processID
    }
    @MainActor private func drain() async {
        while let request = pop() {
            guard allowed(request) else { continue }
            switch request.action {
            case .system(let action):
                let bundle: String
                switch action {
                case .openFinder: bundle = "com.apple.finder"
                case .openSettings: bundle = "com.apple.systempreferences"
                case .activityMonitor: bundle = "com.apple.ActivityMonitor"
                }
                do {
                    let activation = try await (systemOpener ?? NativeSystemApplicationOpener()).open(bundleID: bundle)
                    guard allowed(request) else { continue }
                    if let activation { activation.activate() }
                    else { report("找不到要求開啟的系統 App。") }
                } catch { if allowed(request) { report("系統 App 開啟失敗。") } }
            case .finder(let action): await performFinder(action, request: request)
            case .window(let action): await performWindow(action, request: request)
            case .screenshot(let kind): onScreenshot?(kind, request.source)
            }
        }
    }

    @MainActor private func performFinder(_ action: FinderAction, request: Request) async {
        guard request.context.bundleID == "com.apple.finder" else { return }
        let pid = request.context.processID
        let focus = await Task.detached(priority: .userInitiated) { FinderFocusReader.read(pid: pid) }.value
        guard allowed(request) else { return }
        let pasteboard = NSPasteboard.general
        let now = ProcessInfo.processInfo.systemUptime
        cut.synchronize(epoch: request.generation)
        cut.observe(action)
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
            // A destination folder may have no selection. The armed file clipboard and
            // Finder PID are the move authority; text editing always gets ordinary paste.
            let move = FinderActionPolicy.allowsMove(focus: focus) && pasteboard.types?.contains(.fileURL) == true &&
                cut.consume(changeCount: count, finderPID: pid, now: now)
            cut.cancel()
            guard pasteboard.changeCount == count else { report("剪貼簿已改變，取消本次貼上。"); return }
            if emit(9, move ? [.command, .option] : .command, request: request) {
                report(move ? "已送出 Finder 移動請求；由 Finder 處理確認與結果。" : "已送出 Finder 貼上請求。")
            }
        case .open:
            _ = emit(focus == .files ? 31 : 36, focus == .files ? .command : [], request: request)
        case .rename:
            if focus == .files { _ = emit(36, [], request: request) }
            else { report("F2 改名略過：焦點不是可確認的檔案列表。") }
        case .trash:
            let output = FinderActionPolicy.deleteOutput(focus: focus)
            _ = emit(output.keyCode, output.modifiers, request: request)
        case .permanentDelete:
            cut.cancel()
            guard finderPermanentDeleteEnabled, focus == .files else {
                report("永久刪除略過：設定未啟用或焦點不是檔案列表。"); return
            }
            // Finder's own Delete Immediately (Option-Command-Delete) always asks
            // for confirmation. An in-App modal could not work here: clicking it
            // activated this App, so the Finder-frontmost check then dropped the
            // confirmed request, and the modal blocked every queued action.
            if emit(51, [.command, .option], request: request) {
                report("已請 Finder 永久刪除；請在 Finder 的確認視窗中決定。")
            }
        case .parentFolder:
            if FinderActionPolicy.inFileView(focus) { _ = emit(126, .command, request: request) }
            else { _ = emit(51, [], request: request) }
        case .newFolder:
            if FinderActionPolicy.inFileView(focus) { _ = emit(45, [.command, .shift], request: request) }
            else { report("新增資料夾略過：焦點不是可確認的 Finder 視窗。") }
        case .goToFolder:
            _ = emit(5, [.command, .shift], request: request)
        }
    }

    @MainActor private func performWindow(_ action: WindowAction, request: Request) async {
        guard request.context.mode == .macOS else { return }
        switch action {
        case .close:
            let closed = await Task.detached(priority: .userInitiated) { [self] in
                WindowCloseExecutor.close(pid: request.context.processID) {
                    self.isCurrent(request) && !IsSecureEventInputEnabled()
                }
            }.value
            guard allowed(request) else { return }
            report(closed ? "已請求關閉目前視窗；未儲存內容由 App 原生提示。" : "目前視窗沒有可用的 AX 關閉按鈕；未執行替代關窗或結束 App。")
        }
    }
    /// Complete key pairs, private source, marker and target PID. No global held modifiers.
    @MainActor private func emit(_ key: UInt16, _ modifiers: Modifiers, request: Request,
                                 ignoreDeadline: Bool = false) -> Bool {
        guard allowed(request, ignoreDeadline: ignoreDeadline), let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        for event in [down, up] {
            EventRewriter.apply(to: event, keyCode: key, modifiers: modifiers, marker: marker)
            event.postToPid(request.context.processID)
        }
        return true
    }
}

/// One AX element on the focus chain, from the focused element up to its window.
struct FinderAXNode: Sendable, Equatable {
    var role: String
    var subrole: String = ""
    var identifier: String = ""
    var description: String = ""
    /// A selected child of this element exposes a file URL (read for containers only).
    var selectedFileURL = false
}

enum FinderFocusReader {
    /// Roles that host Finder's file items in list, column, icon and gallery views.
    static let contentRoles: Set<String> = [kAXOutlineRole, kAXTableRole, kAXBrowserRole, kAXListRole, "AXCollection"]
    static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// Positive-evidence classification of a focus chain (focused element first,
    /// window last). `complete` is false when the walk failed or timed out.
    static func classify(_ chain: [FinderAXNode], complete: Bool) -> FinderFocus {
        // Text editing wins even on a partial chain: never turn typing into a file action.
        if chain.contains(where: { textRoles.contains($0.role) || $0.subrole == kAXSearchFieldSubrole }) { return .text }
        guard complete, let window = chain.last, window.role == kAXWindowRole else { return .unknown }
        if window.subrole != kAXStandardWindowSubrole { return .chrome }      // dialogs, panels, unknown windows
        if chain.contains(where: { $0.role == kAXSheetRole || $0.role == kAXToolbarRole }) { return .chrome }
        func mentionsSidebar(_ node: FinderAXNode) -> Bool {
            node.subrole == "AXSourceList" || node.identifier.range(of: "sidebar", options: .caseInsensitive) != nil ||
                node.description.range(of: "sidebar", options: .caseInsensitive) != nil
        }
        if chain.contains(where: mentionsSidebar) { return .sidebar }
        // File content: a content container inside a scroll area (column view: a browser).
        guard let index = chain.firstIndex(where: { contentRoles.contains($0.role) }) else { return .unknown }
        let container = chain[index]
        guard container.role == kAXBrowserRole ||
              chain[(index + 1)...].contains(where: { $0.role == kAXScrollAreaRole || $0.role == kAXBrowserRole }) else { return .unknown }
        return chain[...index].contains(where: \.selectedFileURL) ? .files : .folder
    }

    /// Runs on a worker. Reads roles/identifiers/descriptions of the focus chain and
    /// one selected child's URL, never selected text or document values.
    static func read(pid: Int32) -> FinderFocus {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        var element = unsafeDowncast(focused, to: AXUIElement.self)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        var chain: [FinderAXNode] = []
        func string(_ element: AXUIElement, _ attribute: String) -> String {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? (value as? String ?? "") : ""
        }
        for _ in 0..<10 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return classify(chain, complete: false) }
            AXUIElementSetMessagingTimeout(element, 0.01)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
                  let role = value as? String else { return classify(chain, complete: false) }
            var node = FinderAXNode(role: role, subrole: string(element, kAXSubroleAttribute),
                                    identifier: string(element, kAXIdentifierAttribute))
            if contentRoles.contains(role) || role == kAXScrollAreaRole {
                node.description = string(element, kAXDescriptionAttribute)
                var selection: CFArray?
                // One selected child, never the complete file collection.
                if contentRoles.contains(role),
                   AXUIElementCopyAttributeValues(element, kAXSelectedChildrenAttribute as CFString, 0, 1, &selection) == .success,
                   let selected = (selection as? [AXUIElement])?.first {
                    AXUIElementSetMessagingTimeout(selected, 0.01)
                    var url: CFTypeRef?
                    if AXUIElementCopyAttributeValue(selected, kAXURLAttribute as CFString, &url) == .success,
                       let value = url as? URL, value.isFileURL { node.selectedFileURL = true }
                }
            }
            chain.append(node)
            if role == kAXWindowRole { return classify(chain, complete: true) }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return classify(chain, complete: false) }
            element = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return classify(chain, complete: false)
    }
}

enum WindowCloseExecutor {
    /// Four bounded calls to the focused window only. AXPress preserves the App's save prompt.
    static func close(pid: Int32, valid: () -> Bool) -> Bool {
        guard valid() else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return false }
        let window = unsafeDowncast(windowValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.05)
        var buttonValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &buttonValue) == .success,
              let buttonValue, CFGetTypeID(buttonValue) == AXUIElementGetTypeID() else { return false }
        let button = unsafeDowncast(buttonValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(button, 0.05)
        var enabled: CFTypeRef?
        guard AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &enabled) == .success,
              (enabled as? Bool) == true, valid(), ProcessInfo.processInfo.systemUptime < deadline else { return false }
        var frontmost: CFTypeRef?, currentWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFrontmostAttribute as CFString, &frontmost) == .success,
              (frontmost as? Bool) == true,
              AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &currentWindow) == .success,
              let currentWindow, CFEqual(window, currentWindow), valid(),
              ProcessInfo.processInfo.systemUptime < deadline else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
}
