import AppKit
import SwiftUI
import BridgePlatform

struct PerformanceView: View {
    @StateObject private var monitor: PerformanceMonitor
    init(monitor: PerformanceMonitor = PerformanceMonitor()) { _monitor = StateObject(wrappedValue: monitor) }
    var body: some View {
        PerformanceReadout(snapshot: monitor.snapshot)
            .background(PerformanceVisibilityProbe(onChange: { [weak monitor] visible in monitor?.setVisible(visible) }))
            .onDisappear { monitor.setVisible(false) }
    }
}

struct PerformanceReadout: View {
    let snapshot: PerformanceSnapshot?
    private func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "取樣中…"
    }
    private func bytes(_ value: UInt64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? "無法讀取"
    }
    var body: some View {
        Form {
            Section("整台 Mac") {
                LabeledContent("CPU 使用率", value: percent(snapshot?.systemCPUPercent))
                LabeledContent("記憶體使用量", value: bytes(snapshot?.systemUsedMemory))
                if let value = snapshot, let used = value.systemUsedMemory, value.physicalMemory > 0 {
                    ProgressView(value: Double(used), total: Double(value.physicalMemory))
                        .accessibilityLabel("系統記憶體使用比例")
                }
                LabeledContent("實體記憶體總量", value: bytes(snapshot?.physicalMemory))
                LabeledContent("壓縮記憶體（實際占用）", value: bytes(snapshot?.compressedMemory))
                Text("CPU 以整台 Mac 為 100%。記憶體使用量為活躍、固定與壓縮頁面的合計，可能與活動監視器的分類略有差異。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("WindowsMacBridge 主程式") {
                LabeledContent("CPU 使用率", value: percent(snapshot?.processCPUPercent))
                LabeledContent("記憶體占用", value: bytes(snapshot?.processFootprint))
                Text("CPU 以一個核心為 100%，多核心工作時可超過 100%。記憶體採 physical footprint；不含獨立的 Finder 延伸功能與文字辨識輔助程式。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Label("只在此頁可見時，每 2 秒更新", systemImage: "leaf")
                    .font(.callout)
                Text("切換頁面、視窗被完全遮住、最小化、隱藏 App、關閉視窗或系統休眠時停止取樣。回到此頁會重新計算，不保留歷史紀錄，也不寫入檔案。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).monospacedDigit()
    }
}

private final class PerformanceNotificationBag: @unchecked Sendable {
    var values: [(NotificationCenter, NSObjectProtocol)] = []
    deinit { for (center, token) in values { center.removeObserver(token) } }
}

/// Notification-driven visibility. This observer never runs a polling timer.
/// Only the mounted performance page owns it; queued updates cannot outlive it.
@MainActor final class PerformanceVisibilityView: NSView {
    var onChange: (Bool) -> Void = { _ in }
    private var notifications = PerformanceNotificationBag()
    private var update: DispatchWorkItem?
    private var sleeping = false
    private var displaysSleeping = false
    private var inactiveSession = false
    private var closed = false
    private var lastVisible = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifications = PerformanceNotificationBag()
        closed = false
        guard let window else { stop(); return }
        let center = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification] {
            observe(center, name, object: window) { [weak self] in self?.queueUpdate() }
        }
        observe(center, NSWindow.willCloseNotification, object: window) { [weak self] in
            self?.closed = true; self?.stop()
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observe(center, name, object: nil) { [weak self] in self?.queueUpdate() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.sleeping = true; self?.queueUpdate() }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.sleeping = false; self?.queueUpdate() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.displaysSleeping = true; self?.queueUpdate() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.displaysSleeping = false; self?.queueUpdate() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.inactiveSession = true; self?.queueUpdate() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.inactiveSession = false; self?.queueUpdate() }
        queueUpdate()
    }

    override func viewDidHide() { super.viewDidHide(); queueUpdate() }
    override func viewDidUnhide() { super.viewDidUnhide(); queueUpdate() }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
                         action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        notifications.values.append((center, token))
    }
    private func queueUpdate() {
        update?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.update = nil
                let window = self.window
                let visible = PerformanceVisibility(pageMounted: window != nil && !self.closed && !self.isHiddenOrHasHiddenAncestor,
                    windowVisible: window?.isVisible == true, windowOccluded: window?.occlusionState.contains(.visible) != true,
                    windowMiniaturized: window?.isMiniaturized == true, applicationHidden: NSApp.isHidden,
                    sessionAwake: !self.sleeping && !self.displaysSleeping && !self.inactiveSession).allowsSampling
                if visible != self.lastVisible { self.lastVisible = visible; self.onChange(visible) }
            }
        }
        update = work; DispatchQueue.main.async(execute: work)
    }
    func stop() {
        update?.cancel(); update = nil
        lastVisible = false; onChange(false)
    }
}

private struct PerformanceVisibilityProbe: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> PerformanceVisibilityView {
        let view = PerformanceVisibilityView(); view.onChange = onChange; return view
    }
    func updateNSView(_ view: PerformanceVisibilityView, context: Context) { view.onChange = onChange }
    static func dismantleNSView(_ view: PerformanceVisibilityView, coordinator: ()) { view.stop() }
}
