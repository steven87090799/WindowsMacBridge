import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import BridgeCore
import BridgePlatform

@MainActor final class BridgeController: ObservableObject {
    @Published var status = EngineStatus()
    @Published var context = ApplicationContext()
    @Published var settings: BridgeSettings
    @Published var layoutID = "unknown"
    @Published var layoutSupported = false
    @Published var pauseUntil: Date?
    @Published var pausedUntilRestart = false
    @Published var diagnosticsEnabled = false
    @Published var configurationError: String?
    @Published var targetApp: ApplicationContext?
    private let engine = InputEngine()
    private let store = SettingsStore()
    private var registry: ApplicationRegistry?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sessionActive = true
    private var restartToken: UInt64 = 0
    private var lastEmergency = false
    private var debugUntil: Date?
    var onStatusChange: (() -> Void)?

    var paused: Bool { pausedUntilRestart || (pauseUntil.map { $0 > Date() } ?? false) }
    var summary: String {
        if let configurationError { return configurationError }
        if !settings.enabled { return "已停用" }
        if paused || status.emergencyPaused { return "已暫停" }
        if !status.accessibility { return "等待輔助使用權限" }
        if !status.postAccess { return "等待事件輸出權限" }
        if let fault = status.fault { return fault }
        if !sessionActive { return "Session 暫停" }
        if status.secureInput { return "Secure Input — 原樣通過" }
        if !context.mode.allowsTranslation { return context.mode.title }
        if !layoutSupported { return "此輸入來源尚未支援 — 原樣通過" }
        if !status.tapActive { return "Event Tap 尚未啟用" }
        if status.awaitingNeutral { return "請放開所有按鍵" }
        return "Windows Mode：ON"
    }

    init() {
        settings = store.settings
        configurationError = store.errorMessage
        do { registry = try ApplicationRegistry() }
        catch { configurationError = "App 保護清單無法載入；翻譯已停用。" }
    }
    func start() {
        refreshApplication()
        refreshLayout()
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { $0.refreshApplication() }
        observe(center, NSWorkspace.didTerminateApplicationNotification) { $0.refreshApplication() }
        observe(center, NSWorkspace.willSleepNotification) { $0.setSession(false) }
        observe(center, NSWorkspace.didWakeNotification) { $0.setSession(true); $0.refreshApplication() }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.setSession(false) }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSession(true); $0.refreshApplication() }
        engine.start()
        publish()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (BridgeController) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
        })
    }
    func stop() {
        timer?.invalidate(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        engine.stop()
    }
    private func tick() {
        status = engine.snapshot()
        refreshLayout()
        if let until = pauseUntil, until <= Date() { resume() }
        if let until = debugUntil, until <= Date() { setDiagnostics(false) }
        if status.emergencyPaused && !lastEmergency {
            pausedUntilRestart = true; pauseUntil = nil; publish()
        }
        lastEmergency = status.emergencyPaused
        onStatusChange?()
    }
    private func refreshLayout() {
        let current = KeyboardLayoutResolver.current()
        if layoutID != current.id || layoutSupported != current.supported {
            layoutID = current.id; layoutSupported = current.supported; publish()
        }
    }
    private func refreshApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            context = ApplicationContext(); publish(); return
        }
        let bundle = app.bundleIdentifier ?? ""
        var mode = registry?.mode(for: bundle, overrides: settings.overrides) ?? .disabled
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { mode = .disabled }
        context = ApplicationContext(processID: app.processIdentifier, bundleID: bundle,
                                     displayName: app.localizedName ?? "Unknown", mode: mode)
        if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { targetApp = context }
        publish()
    }
    private func setSession(_ active: Bool) { sessionActive = active; publish() }
    private func publish() {
        var config = EngineConfiguration()
        config.context = context
        config.enabled = settings.enabled && !paused && registry != nil && configurationError == nil
        config.sessionActive = sessionActive
        config.layoutSupported = layoutSupported
        config.diagnostics = diagnosticsEnabled
        config.restartToken = restartToken
        engine.update(config)
    }
    func setEnabled(_ value: Bool) {
        store.update { $0.enabled = value }; settings = store.settings
        configurationError = store.errorMessage
        if value { resume() } else { publish() }
    }
    func pause(minutes: Int?) {
        pauseUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        pausedUntilRestart = minutes == nil
        publish(); onStatusChange?()
    }
    func resume() {
        pauseUntil = nil; pausedUntilRestart = false
        restartToken &+= 1; publish(); onStatusChange?()
    }
    func setDiagnostics(_ enabled: Bool) {
        diagnosticsEnabled = enabled
        debugUntil = enabled ? Date().addingTimeInterval(300) : nil
        publish()
    }
    func assign(_ mode: ApplicationMode, bundleID: String) {
        guard !bundleID.isEmpty else { return }
        store.update { $0.overrides[bundleID] = mode }
        settings = store.settings; configurationError = store.errorMessage
        refreshApplication()
    }
    func removeOverride(_ bundleID: String) {
        store.update { $0.overrides.removeValue(forKey: bundleID) }
        settings = store.settings; refreshApplication()
    }
    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "加入原樣通過清單"
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            assign(.disabled, bundleID: id)
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func requestListening() { _ = CGRequestListenEventAccess() }
    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
