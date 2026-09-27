import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import BridgeCore
import BridgePlatform
import InputSourceSupport
import InputSourceCore
import HIDProtocol

@MainActor final class BridgeController: ObservableObject {
    let inputSources = InputSourceCoordinator()
    @Published var sourceStatus = InputSourceStatus()
    @Published var sourceDiagnostics = ""
    @Published var sourceLog = ""
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
    @Published var hidStatus = HIDStatus()
    private let engine = InputEngine()
    private let hid = HIDBackendClient()
    private let store = SettingsStore()
    private var registry: ApplicationRegistry?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private enum SuspensionReason { case systemSleep, screensSleep, inactiveSession }
    private var suspensionReasons = Set<SuspensionReason>()
    private var sessionActive: Bool { suspensionReasons.isEmpty }
    private var legacyAppRunning = false
    private var restartToken: UInt64 = 0
    private var lastEmergency = false
    private var debugUntil: Date?
    var onStatusChange: (() -> Void)?

    var paused: Bool { pausedUntilRestart || (pauseUntil.map { $0 > Date() } ?? false) }
    var summary: String {
        if let configurationError { return configurationError }
        if !settings.enabled { return "已停用" }
        if paused || status.emergencyPaused { return "已暫停" }
        if settings.inputBackend == .deviceHID {
            if settings.keyboardScope != .builtInAndApple834 { return "HID 後端僅支援指定鍵盤範圍" }
            if hidStatus.manualPassThrough { return "右 Option+P 穿透：ON" }
            if hidStatus.capturedDevices == 0 { return hidStatus.state }
            if !context.mode.allowsTranslation { return context.mode.title }
            return "Windows HID Mode：ON（\(hidStatus.capturedDevices) 個裝置）"
        }
        if status.manualPassThrough { return "右 Option+P 穿透：ON" }
        if let issue = status.backendIssue { return issue }
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
        inputSources.onChange = { [weak self] status in
            guard let self else { return }
            sourceStatus = status
            refreshLayout()
            onStatusChange?()
        }
        inputSources.liveSelectionAllowed = { [weak self] in
            guard let self else { return false }
            return !InputSourceCoordinator.legacyAppRunning && sourceSuspension(for: currentApplicationContext()) == nil
        }
        refreshLegacyApplication()
        refreshApplication()
        refreshLayout()
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { $0.refreshApplication() }
        observe(center, NSWorkspace.didTerminateApplicationNotification) { $0.refreshLegacyApplication(); $0.refreshApplication() }
        observe(center, NSWorkspace.didLaunchApplicationNotification) { $0.refreshLegacyApplication(); $0.publish() }
        observe(center, NSWorkspace.willSleepNotification) { $0.setSuspended(.systemSleep, true) }
        observe(center, NSWorkspace.didWakeNotification) { $0.setSuspended(.systemSleep, false); $0.refreshApplication() }
        observe(center, NSWorkspace.screensDidSleepNotification) { $0.setSuspended(.screensSleep, true) }
        observe(center, NSWorkspace.screensDidWakeNotification) { $0.setSuspended(.screensSleep, false) }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.setSuspended(.inactiveSession, true) }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSuspended(.inactiveSession, false); $0.refreshApplication() }
        inputSources.start()
        engine.start()
        hid.start()
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
        inputSources.stop()
        engine.stop()
        hid.stop()
    }
    private func tick() {
        let previousPassThrough = status.manualPassThrough
        status = engine.snapshot()
        if settings.inputBackend == .deviceHID {
            hidStatus = hid.status
            status.manualPassThrough = hidStatus.manualPassThrough
            status.emergencyPaused = hidStatus.emergencyPaused
            status.secureInput = hidStatus.secureInput
            status.processed = hidStatus.processed; status.translated = hidStatus.translated
            status.maxMicroseconds = hidStatus.maxMicroseconds
            status.actionStatus = hid.actionStatus
            status.backendIssue = nil
        }
        if previousPassThrough != status.manualPassThrough {
            inputSources.updateProtection(sourceSuspension(for: context))
        }
        if let until = pauseUntil, until <= Date() { resume() }
        if let until = debugUntil, until <= Date() { setDiagnostics(false) }
        if status.emergencyPaused && !lastEmergency {
            pausedUntilRestart = true; pauseUntil = nil; publish()
        }
        lastEmergency = status.emergencyPaused
        onStatusChange?()
    }
    private func refreshLayout() {
        let current = KeyboardLayoutResolver.current(allowIME: settings.allowIMEShortcuts)
        let supported = current.supported && !sourceStatus.selectionInProgress
        if layoutID != current.id || layoutSupported != supported {
            layoutID = current.id; layoutSupported = supported; publish()
        }
    }
    private func currentApplicationContext() -> ApplicationContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return ApplicationContext() }
        let bundle = app.bundleIdentifier ?? ""
        let path = app.executableURL?.path ?? ""
        var mode = registry?.mode(for: bundle, executablePath: path, overrides: settings.overrides) ?? .disabled
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { mode = .disabled }
        return ApplicationContext(processID: app.processIdentifier, bundleID: bundle,
                                  displayName: app.localizedName ?? "Unknown", mode: mode,
                                  executablePath: path, isBrowser: registry?.isBrowser(bundle) ?? false)
    }
    private func refreshApplication() {
        context = currentApplicationContext()
        if context.processID != ProcessInfo.processInfo.processIdentifier { targetApp = context }
        refreshLayout()
        publish()
    }
    private func refreshLegacyApplication() { legacyAppRunning = InputSourceCoordinator.legacyAppRunning }
    private func sourceSuspension(for app: ApplicationContext) -> InputSourceSuspension? {
        InputSourcePolicy.suspension(context: app,
            isHostApp: app.processID == ProcessInfo.processInfo.processIdentifier,
            paused: paused || status.emergencyPaused || status.manualPassThrough, sessionActive: sessionActive,
            legacyAppRunning: legacyAppRunning)
    }
    private func setSuspended(_ reason: SuspensionReason, _ suspended: Bool) {
        if suspended { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        publish()
    }
    func refreshSourceDiagnostics() {
        sourceDiagnostics = inputSources.diagnostics
        sourceLog = inputSources.recentLog
        sourceStatus = inputSources.status
    }
    private func publish() {
        var config = EngineConfiguration()
        config.context = context
        config.enabled = settings.enabled && !paused && registry != nil && configurationError == nil
        config.sessionActive = sessionActive
        config.layoutSupported = layoutSupported
        config.diagnostics = diagnosticsEnabled
        config.restartToken = restartToken
        config.keyboardScope = settings.keyboardScope
        config.finderEnabled = settings.finderEnabled
        hid.update(config, active: settings.inputBackend == .deviceHID)
        config.enabled = config.enabled && settings.inputBackend == .eventTap
        engine.update(config)
        inputSources.updateProtection(sourceSuspension(for: context))
    }
    func setEnabled(_ value: Bool) {
        store.update { $0.enabled = value }; settings = store.settings
        configurationError = store.errorMessage
        if value { resume() } else { publish() }
    }
    func setKeyboardScope(_ value: KeyboardScope) {
        store.update { $0.keyboardScope = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setInputBackend(_ value: InputBackend) {
        store.update { $0.inputBackend = value
            $0.keyboardScope = value == .deviceHID ? .builtInAndApple834 : .allKeyboards
        }
        settings = store.settings; configurationError = store.errorMessage
        restartToken &+= 1; publish()
    }
    func openHelperLocation() {
        NSWorkspace.shared.selectFile(HIDService.root + "/BridgeHIDHelper.app", inFileViewerRootedAtPath: HIDService.root)
    }
    func requestHIDListening() { hid.requestInputAccess() }
    func setFinderEnabled(_ value: Bool) {
        store.update { $0.finderEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setIMEShortcuts(_ value: Bool) {
        store.update { $0.allowIMEShortcuts = value }; settings = store.settings
        configurationError = store.errorMessage; refreshLayout()
    }
    func pause(minutes: Int?) {
        pauseUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        pausedUntilRestart = minutes == nil
        publish(); onStatusChange?()
    }
    func resume() {
        pauseUntil = nil; pausedUntilRestart = false; status.emergencyPaused = false
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
