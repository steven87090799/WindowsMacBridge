import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import BridgeCore
import BridgePlatform
import InputSourceSupport
import InputSourceCore
import HIDProtocol
import FinderSync

@MainActor final class BridgeController: ObservableObject {
    @Published var settingsPage = SettingsPage.permissions
    let inputSources = InputSourceCoordinator()
    @Published var sourceStatus = InputSourceStatus()
    @Published var sourceDiagnostics = ""
    @Published var sourceMemoryUsage = "尚未讀取"
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
    @Published var presetNotice: String?
    @Published var targetApp: ApplicationContext?
    @Published var hidStatus = HIDStatus()
    @Published var screenshotStatus = ScreenshotStatus()
    @Published private(set) var permissionChecklist = PermissionChecklistState()
    var permissions: PermissionSnapshot { permissionChecklist.verified }
    @Published private(set) var permissionsCheckedAt: Date?
    var finderExtensionEnabled: Bool { permissions.finderExtension }
    var screenRecordingGranted: Bool { permissions.screenRecording }
    private let engine = InputEngine()
    private let hid = HIDBackendClient()
    private let store = SettingsStore()
    private let screenshot = ScreenshotManager()
    private let screenshotManagedLoginKey = "screenshot.loginManaged.v1"
    private var registry: ApplicationRegistry?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private enum SuspensionReason { case systemSleep, screensSleep, inactiveSession }
    private var suspensionReasons = Set<SuspensionReason>()
    private var sessionActive: Bool { suspensionReasons.isEmpty }
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
        refreshPermissions()
        configurationError = store.errorMessage
        do { registry = try ApplicationRegistry() }
        catch { configurationError = "App 保護清單無法載入；翻譯已停用。" }
    }
    func start() {
        syncFinderExtensionPreference()
        inputSources.onChange = { [weak self] status in
            guard let self else { return }
            let loginChanged = sourceStatus.loginStatus != status.loginStatus
            if sourceStatus != status { sourceStatus = status }
            if loginChanged { refreshPermissions() }
            refreshLayout()
            onStatusChange?()
        }
        inputSources.liveSelectionAllowed = { [weak self] in
            guard let self else { return false }
            return sourceSuspension(for: currentApplicationContext()) == nil
        }
        refreshApplication()
        refreshLayout()
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { $0.refreshApplication() }
        observe(center, NSWorkspace.didTerminateApplicationNotification) { $0.refreshApplication() }
        observe(center, NSWorkspace.willSleepNotification) { $0.setSuspended(.systemSleep, true) }
        observe(center, NSWorkspace.didWakeNotification) { $0.setSuspended(.systemSleep, false); $0.refreshApplication() }
        observe(center, NSWorkspace.screensDidSleepNotification) { $0.setSuspended(.screensSleep, true) }
        observe(center, NSWorkspace.screensDidWakeNotification) { $0.setSuspended(.screensSleep, false) }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { $0.setSuspended(.inactiveSession, true) }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSuspended(.inactiveSession, false); $0.refreshApplication() }
        inputSources.start()
        screenshot.onChange = { [weak self] status in self?.screenshotStatus = status }
        screenshot.onPeriodicCheck = { [weak self] in self?.verifyScreenshotConfiguration() }
        screenshot.start(enabled: settings.screenshotAutoCopy)
        if settings.screenshotAutoCopy { ensureScreenshotLogin() }
        refreshPermissions()
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
        screenshot.stop()
        engine.stop()
        hid.stop()
    }
    private func tick() {
        let previousPassThrough = status.manualPassThrough
        let previousAccessibility = status.accessibility
        let previousPosting = status.postAccess
        let previousListening = status.listenAccess
        var next = engine.snapshot()
        if settings.inputBackend == .deviceHID {
            if hidStatus != hid.status { hidStatus = hid.status }
            next.manualPassThrough = hidStatus.manualPassThrough
            next.emergencyPaused = hidStatus.emergencyPaused
            next.secureInput = hidStatus.secureInput
            next.processed = hidStatus.processed; next.translated = hidStatus.translated
            next.maxMicroseconds = hidStatus.maxMicroseconds
            next.actionStatus = hid.actionStatus
            next.backendIssue = nil
        }
        // Publishing identical snapshots wakes SwiftUI even when no window is visible.
        let changed = status != next
        if changed { status = next }
        // A cached engine snapshot is not proof of authorization. A transition
        // triggers a native recheck, never an optimistic green checkmark.
        if permissionChecklist.awaitingVerification.isEmpty &&
            (previousAccessibility != next.accessibility || previousPosting != next.postAccess ||
             previousListening != next.listenAccess) {
            refreshPermissions()
        }
        if !previousAccessibility && next.accessibility && settings.screenshotAutoCopy {
            screenshot.verifyAndRepair(reason: "輔助使用權限恢復")
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
        if changed { onStatusChange?() }
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
        if context.processID == ProcessInfo.processInfo.processIdentifier { refreshPermissions() }
        if context.processID != ProcessInfo.processInfo.processIdentifier { targetApp = context }
        refreshLayout()
        publish()
    }
    func refreshPermissions() {
        // A source/login notification in the background must not confirm a
        // settings link. Verify once the user returns, or explicitly rechecks.
        if !permissionChecklist.awaitingVerification.isEmpty && !NSApp.isActive { return }
        var next = permissionChecklist
        next.verify(PermissionStatus.current())
        if permissionChecklist != next { permissionChecklist = next }
        permissionsCheckedAt = Date()
    }
    func openPermissionSettings(_ kind: PermissionKind) {
        var next = permissionChecklist
        next.beginNavigation(to: kind)
        permissionChecklist = next
        // These links only navigate. Request APIs and login registration belong
        // to explicit feature controls, and their return values are not grants.
        switch kind {
        case .accessibility, .posting: openPermissions()
        case .listening: openInputMonitoring()
        case .screenRecording: openScreenRecording()
        case .finderExtension: openFinderExtensionSettings()
        case .loginItem: inputSources.openLoginSettings()
        }
    }
    private func sourceSuspension(for app: ApplicationContext) -> InputSourceSuspension? {
        InputSourcePolicy.suspension(context: app,
            isHostApp: app.processID == ProcessInfo.processInfo.processIdentifier,
            paused: paused || status.emergencyPaused || status.manualPassThrough, sessionActive: sessionActive)
    }
    private func setSuspended(_ reason: SuspensionReason, _ suspended: Bool) {
        if suspended { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        if !suspended && settings.screenshotAutoCopy { screenshot.verifyAndRepair(reason: "Session 恢復") }
        publish()
    }
    func setScreenshotAutoCopy(_ value: Bool) {
        store.update { $0.screenshotAutoCopy = value }
        settings = store.settings
        configurationError = store.errorMessage
        guard store.errorMessage == nil else { return }
        screenshot.setEnabled(value)
        if value {
            ensureScreenshotLogin()
        } else if UserDefaults.standard.bool(forKey: screenshotManagedLoginKey) {
            inputSources.setLoginEnabled(false)
            if !inputSources.loginIsRegistered {
                UserDefaults.standard.removeObject(forKey: screenshotManagedLoginKey)
            }
        }
    }
    private func ensureScreenshotLogin() {
        let wasRegistered = inputSources.loginIsRegistered
        if inputSources.ensureLoginEnabled(), !wasRegistered {
            UserDefaults.standard.set(true, forKey: screenshotManagedLoginKey)
            screenshot.recordRepair("登入啟動已註冊")
        }
        if !inputSources.loginIsActive {
            screenshot.reportConfigurationIssue("登入啟動未生效（\(inputSources.loginStatusText)）；請在系統設定核准登入項目。")
        }
    }
    private func verifyScreenshotConfiguration() {
        guard settings.screenshotAutoCopy else { return }
        let stored = SettingsStore().settings
        if !stored.screenshotAutoCopy {
            store.update { $0.screenshotAutoCopy = true }
            settings = store.settings
            if store.errorMessage != nil {
                screenshot.reportConfigurationIssue("截圖設定無法持久儲存。")
            } else {
                screenshot.recordRepair("持久設定已重新寫入")
            }
        }
        ensureScreenshotLogin()
    }
    var screenshotLogPath: String { screenshot.logPath }
    func refreshSourceDiagnostics() {
        sourceDiagnostics = inputSources.diagnostics
        sourceLog = inputSources.recentLog
        sourceStatus = inputSources.status
    }
    func refreshSourceStatistics() {
        sourceStatus = inputSources.status
        sourceMemoryUsage = inputSources.memoryUsageDescription
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
        config.finderPermanentDeleteEnabled = settings.finderPermanentDeleteEnabled
        config.textNavigationEnabled = settings.textNavigationEnabled
        config.windowSwitcherEnabled = settings.windowSwitcherEnabled
        config.windowThumbnailsEnabled = settings.windowThumbnailsEnabled
        config.altF4Enabled = settings.altF4Enabled
        config.altF4QuitLastWindow = settings.altF4QuitLastWindow
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
    func applyRecommendedPreset() {
        store.applyRecommendedPreset()
        settings = store.settings; configurationError = store.errorMessage
        if let error = store.errorMessage { presetNotice = error; publish(); return }
        syncFinderExtensionPreference()
        refreshApplication()
        resume()
        presetNotice = "已套用建議預設並恢復引擎。"
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
    func openUserGuide() {
        if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }
    func openAcceptanceGuide() {
        if let url = Bundle.main.url(forResource: "AcceptanceGuide", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }
    func setFinderEnabled(_ value: Bool) {
        store.update { $0.finderEnabled = value }; settings = store.settings
        if store.errorMessage == nil { syncFinderExtensionPreference() }
        configurationError = store.errorMessage; publish()
    }
    private func syncFinderExtensionPreference() {
        guard let defaults = UserDefaults(suiteName: "group.local.WindowsMacBridge") else { return }
        defaults.set(settings.finderEnabled, forKey: "finder.enabled")
        defaults.synchronize()
    }
    func openFinderExtensionSettings() { FIFinderSyncController.showExtensionManagementInterface() }
    func setFinderPermanentDeleteEnabled(_ value: Bool) {
        store.update { $0.finderPermanentDeleteEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setTextNavigationEnabled(_ value: Bool) {
        store.update { $0.textNavigationEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setWindowSwitcherEnabled(_ value: Bool) {
        store.update { $0.windowSwitcherEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setWindowThumbnailsEnabled(_ value: Bool) {
        store.update { $0.windowThumbnailsEnabled = value }; settings = store.settings
        configurationError = store.errorMessage
        if value && !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        refreshPermissions()
        publish()
    }
    func setAltF4Enabled(_ value: Bool) {
        store.update { $0.altF4Enabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setAltF4QuitLastWindow(_ value: Bool) {
        store.update { $0.altF4QuitLastWindow = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func openScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    func requestScreenRecording() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        refreshPermissions()
    }
    func openInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
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
        panel.prompt = "加入 App 規則"
        panel.message = "加入後先使用原樣通過；回到 App 規則頁選擇要套用的 Profile。"
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            assign(.disabled, bundleID: id)
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
    }
    func requestListening() { _ = CGRequestListenEventAccess(); refreshPermissions() }
    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
