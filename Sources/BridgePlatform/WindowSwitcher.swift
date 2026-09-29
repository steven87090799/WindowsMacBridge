import AppKit
import ApplicationServices
import BridgeCore
import ScreenCaptureKit
import SwiftUI

/// Accessibility work stays on the action/UI path, outside the keyboard callback.
@MainActor final class WindowSwitcher {
    private struct Item: Identifiable {
        let id: String
        let app: NSRunningApplication
        let window: AXUIElement
        let title: String
        let icon: NSImage
        let minimized: Bool
        var thumbnail: NSImage?
    }
    private var items: [Item] = []
    private var recent = WindowHistory()
    private var cycle = WindowCycle()
    private var panel: NSPanel?
    var thumbnailsEnabled = false
    private var thumbnailTask: Task<Void, Never>?
    private var observers: [Int32: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private(set) var status = "視窗切換待命"

    func startObserving() {
        guard workspaceTokens.isEmpty else { return }
        for app in candidateApps() {
            observe(app.processIdentifier)
        }
        recordFocused(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                   object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.observe(app.processIdentifier) }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                   object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.recordFocused(app.processIdentifier) }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                   object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.removeObserver(app.processIdentifier, discardHistory: true) }
        })
    }

    func stopObserving() {
        cancel()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        for pid in Array(observers.keys) { removeObserver(pid) }
    }

    private func observe(_ pid: Int32) {
        guard pid != ProcessInfo.processInfo.processIdentifier, observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            MainActor.assumeIsolated {
                let instance = Unmanaged<WindowSwitcher>.fromOpaque(refcon).takeUnretainedValue()
                instance.recordFocused(pid)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        observers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func removeObserver(_ pid: Int32, discardHistory: Bool = false) {
        if discardHistory { recent.remove(processID: pid) }
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func recordFocused(_ pid: Int32?) {
        guard let pid = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let id = "\(pid):\(CFHash(focused))"
        recent.record(id)
    }

    func cancel() {
        thumbnailTask?.cancel(); thumbnailTask = nil
        panel?.orderOut(nil); panel = nil; items.removeAll(); cycle.reset()
    }

    func advance(reverse: Bool) {
        if items.isEmpty {
            items = collect()
            guard !items.isEmpty else { status = "沒有可切換的視窗。"; return }
        }
        cycle.advance(count: items.count, reverse: reverse)
        show()
        if thumbnailsEnabled && thumbnailTask == nil && CGPreflightScreenCaptureAccess() {
            thumbnailTask = Task { await captureThumbnails() }
        }
    }

    func commit() {
        guard let selected = cycle.commit(), items.indices.contains(selected) else { cancel(); return }
        let item = items[selected]
        cancel()
        if item.minimized {
            _ = AXUIElementSetAttributeValue(item.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        _ = item.app.activate()
        let result = AXUIElementPerformAction(item.window, kAXRaiseAction as CFString)
        let focused = AXUIElementSetAttributeValue(item.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        status = result == .success || focused == .success ? "已切換：\(item.title)" : "視窗無法聚焦（AX \(result.rawValue)）。"
        recent.record(item.id)
    }

    func standardWindowCount(pid: Int32) -> Int {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return 0 }
        return windows.filter { window in
            var subrole: CFTypeRef?
            return AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success &&
                (subrole as? String) == (kAXStandardWindowSubrole as String)
        }.count
    }

    private func collect() -> [Item] {
        let zOrder = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]) ?? []
        var visibleOrder: [String: Int] = [:]
        for (index, entry) in zOrder.enumerated() {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  let title = entry[kCGWindowName as String] as? String else { continue }
            visibleOrder["\(pid):\(title)"] = min(visibleOrder["\(pid):\(title)"] ?? index, index)
        }
        var result: [Item] = []
        for app in candidateApps() {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.08)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows.prefix(64) where result.count < 256 {
                AXUIElementSetMessagingTimeout(window, 0.08)
                var role: CFTypeRef?, subrole: CFTypeRef?, titleValue: CFTypeRef?, minimizedValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
                      (role as? String) == (kAXWindowRole as String) else { continue }
                _ = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
                if let subrole = subrole as? String, subrole != (kAXStandardWindowSubrole as String) { continue }
                _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                _ = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                let title = (titleValue as? String).flatMap { $0.isEmpty ? nil : $0 } ?? app.localizedName ?? "Window"
                let id = "\(app.processIdentifier):\(CFHash(window))"
                result.append(Item(id: id, app: app, window: window, title: title,
                                   icon: app.icon ?? NSImage(), minimized: (minimizedValue as? Bool) ?? false,
                                   thumbnail: nil))
            }
        }
        return result.sorted { lhs, rhs in
            let leftRecent = recent.rank(of: lhs.id)
            let rightRecent = recent.rank(of: rhs.id)
            if leftRecent != rightRecent { return leftRecent < rightRecent }
            let leftOrder = visibleOrder["\(lhs.app.processIdentifier):\(lhs.title)"] ?? Int.max
            let rightOrder = visibleOrder["\(rhs.app.processIdentifier):\(rhs.title)"] ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id < rhs.id
        }
    }

    private func candidateApps() -> [NSRunningApplication] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return Array(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { lhs, rhs in
                if lhs.processIdentifier == front { return true }
                if rhs.processIdentifier == front { return false }
                return lhs.processIdentifier < rhs.processIdentifier
            }.prefix(64))
    }

    private func show() {
        let rows = items.enumerated().map { index, item in
            WindowRow(icon: item.icon, app: item.app.localizedName ?? "App", title: item.title,
                      minimized: item.minimized, selected: index == cycle.selectedIndex, thumbnail: item.thumbnail)
        }
        let content = NSHostingView(rootView: WindowSwitcherView(rows: rows))
        let height = min(520, max(80, rows.count * 51 + 30))
        let frame = NSRect(x: 0, y: 0, width: 520, height: height)
        if panel == nil {
            let created = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.level = .floating
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            panel = created
        }
        panel?.contentView = content
        panel?.setContentSize(frame.size)
        if let screen = NSScreen.main {
            panel?.setFrameOrigin(NSPoint(x: screen.frame.midX - frame.width / 2,
                                          y: screen.frame.midY - frame.height / 2))
        }
        panel?.orderFrontRegardless()
        if let selected = cycle.selectedIndex {
            status = "視窗 \(selected + 1)/\(items.count)：\(items[selected].title)"
        }
    }

    private func captureThumbnails() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            for index in items.indices.prefix(12) {
                if Task.isCancelled { return }
                let item = items[index]
                guard let window = content.windows.first(where: {
                    $0.owningApplication?.processID == item.app.processIdentifier && $0.title == item.title
                }) else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = 160
                config.height = max(1, Int(160 * window.frame.height / max(1, window.frame.width)))
                do {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    if Task.isCancelled { return }
                    if items.indices.contains(index) && items[index].id == item.id {
                        items[index].thumbnail = NSImage(cgImage: image, size: .zero)
                        show()
                    }
                } catch { status = "縮圖擷取失敗；仍可用標題切換。" }
            }
        } catch { status = "無法取得視窗縮圖；請確認螢幕錄製權限。" }
    }
}

private struct WindowRow {
    let icon: NSImage
    let app: String
    let title: String
    let minimized: Bool
    let selected: Bool
    let thumbnail: NSImage?
}

private struct WindowSwitcherView: View {
    let rows: [WindowRow]
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack(spacing: 10) {
                        Image(nsImage: row.icon).resizable().frame(width: 28, height: 28)
                        if let thumbnail = row.thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 64, height: 36)
                        }
                        VStack(alignment: .leading) {
                            Text(row.title).lineLimit(1)
                            Text(row.app + (row.minimized ? " · 已最小化" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(row.selected ? Color.accentColor.opacity(0.3) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }.padding(12)
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
    }
}
