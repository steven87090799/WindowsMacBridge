import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import BridgeCore
import BridgePlatform
import InputSourceSupport
import InputSourceCore
import HIDProtocol
import FinderSync
import Carbon

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
    @Published var macBookKeyboardStatus = MacBookKeyboardMappingStatus()
    @Published private(set) var permissionChecklist = PermissionChecklistState()
    var permissions: PermissionSnapshot { permissionChecklist.verified }
    @Published private(set) var permissionsCheckedAt: Date?
    var finderExtensionEnabled: Bool { permissions.finderExtension }
    private let engine = InputEngine()
    private let hid = HIDBackendClient()
    private let store = SettingsStore()
    private let installationRecoveryPending: Bool
    private let screenshot = ScreenshotManager()
    private let macBookKeyboard = MacBookKeyboardMapper()
    private let finderPublisher = FinderModePublisher()
    private let screenshotManagedLoginKey = "screenshot.loginManaged.v1"
    private let macBookManagedLoginKey = "macbook.loginManaged.v1"
    private var registry: ApplicationRegistry?
    private var timer: Timer?
    private var timerPlan: RuntimeWakePlan = .stopped
    private var running = false
    private var observers: [NSObjectProtocol] = []
    private enum SuspensionReason { case systemSleep, screensSleep, inactiveSession }
    private var suspensionReasons = Set<SuspensionReason>()
    private var sessionActive: Bool { suspensionReasons.isEmpty }
    private var restartToken: UInt64 = 0
    private var lastEmergency = false
    private var policy = RuntimePolicyCoordinator()
    private var settingsRevision: UInt64 = 0
    private var sessionEpoch: UInt64 = 0
    private var lastAppliedSettings: BridgeSettings?
    private var transitionApplying = false
    private var transitionRequested = false
    private var debugUntil: Date?
    var onStatusChange: (() -> Void)?

    var paused: Bool { pausedUntilRestart || (pauseUntil.map { $0 > Date() } ?? false) }
    var summary: String {
        if installationRecoveryPending { return "更新尚未復原；請重新執行 HID Install.command，完成後重開 App。" }
        if let configurationError { return configurationError }
        if !settings.enabled { return "已停用" }
        if paused || status.emergencyPaused { return "已暫停" }
        if !settings.remoteInputProfile.translates { return settings.remoteInputProfile.title }
        if hid.releasePending { return "等待 Helper 安全釋放；新後端尚未啟動" }
        if settings.inputBackend == .deviceHID {
            if macBookKeyboardStatus.restorePending { return "等待 Fn／Ctrl 原生交換還原；HID 尚未啟動" }
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
        installationRecoveryPending = FileManager.default.fileExists(atPath: HIDService.root + "/.install-recovery")
        settings = store.settings
        refreshPermissions()
        configurationError = store.errorMessage
        do { registry = try ApplicationRegistry() }
        catch { configurationError = "App 保護清單無法載入；翻譯已停用。" }
    }
    func start() {
        guard !running else { return }
        running = true
        macBookKeyboard.onChange = { [weak self] status in
            guard let self else { return }
            let wasPending = macBookKeyboardStatus.restorePending
            macBookKeyboardStatus = status
            updateRuntimeTimer()
            if wasPending != status.restorePending { publish() }
        }
        macBookKeyboard.onDiagnostic = { KeyboardMappingDiagnostics.append($0) }
        finderPublisher.start(enabled: false)
        inputSources.onChange = { [weak self] status in
            guard let self, running else { return }
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
        screenshot.start(enabled: false)
        hid.onOwnershipChange = { [weak self] in self?.publish() }
        hid.onScreenshot = { [weak self] kind in self?.screenshot.requestCapture(kind) }
        if settings.screenshotAutoCopy { ensureScreenshotLogin() }
        if settings.macBookFnControlSwap { ensureMacBookLogin() }
        refreshPermissions()
        engine.start()
        hid.start()
        publish()
        updateRuntimeTimer()
    }
    private func updateRuntimeTimer() {
        guard running, let snapshot = policy.current else { return }
        let deadline = [pauseUntil, debugUntil].compactMap { $0?.timeIntervalSince1970 }.min()
        let plan = RuntimeWakePlan.make(input: snapshot.input,
                                        awaitingMappingNeutral: macBookKeyboardStatus.awaitingNeutral,
                                        deadline: deadline)
        guard plan != timerPlan || (timer == nil && plan != .stopped) else { return }
        timer?.invalidate(); timer = nil; timerPlan = plan
        let interval: Double
        switch plan {
        case .stopped: return
        case .periodic: interval = 1
        case .deadline(let time): interval = max(0.01, time - Date().timeIntervalSince1970)
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: plan == .periodic) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                if self.timerPlan != .periodic { self.timer = nil; self.timerPlan = .stopped }
                self.tick(); self.updateRuntimeTimer()
            }
        }
        timer?.tolerance = plan == .periodic ? 0.1 : 0.01
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (BridgeController) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.running { action(self) } }
        })
    }
    func stop() {
        running = false
        finderPublisher.stop()
        timer?.invalidate(); timer = nil; timerPlan = .stopped
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        screenshot.stop()
        // Restoring a pending lease during quit must not re-enable the HID backend.
        macBookKeyboard.onChange = nil
        macBookKeyboard.stop()
        engine.stop()
        hid.onOwnershipChange = nil
        hid.stop()
        inputSources.stop()
    }
    private func tick() {
        // Reuse the existing lifecycle tick only while a mapping mutation is waiting.
        if macBookKeyboardStatus.awaitingNeutral { refreshMacBookKeyboard() }
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
        if previousAccessibility != next.accessibility && settings.screenshotAutoCopy && settings.inputBackend == .eventTap {
            screenshot.verifyAndRepair(reason: next.accessibility ? "輔助使用權限恢復" : "輔助使用權限失效")
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
        publish()
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
    func refreshPermissions(userInitiated: Bool = false) {
        // A source/login notification in the background must not confirm a
        // settings link. Verify once the user returns, or explicitly rechecks.
        if !userInitiated && !permissionChecklist.awaitingVerification.isEmpty && !NSApp.isActive { return }
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
        if installationRecoveryPending { return .protectedApplication }
        if !settings.remoteInputProfile.translates || IsSecureEventInputEnabled() { return .protectedApplication }
        return InputSourcePolicy.suspension(context: app,
            isHostApp: app.processID == ProcessInfo.processInfo.processIdentifier,
            paused: paused || status.emergencyPaused || status.manualPassThrough, sessionActive: sessionActive)
    }
    private func setSuspended(_ reason: SuspensionReason, _ suspended: Bool) {
        if suspended { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        sessionEpoch &+= 1
        if !suspended && settings.screenshotAutoCopy && settings.inputBackend == .eventTap {
            screenshot.verifyAndRepair(reason: "Session 恢復")
        }
        publish()
    }
    private func configureMacBookKeyboard() {
        let native = settings.inputBackend == .eventTap ||
            HIDCapturePolicy.requiresNativePassThrough(mode: context.mode, layoutSupported: layoutSupported) ||
            !settings.remoteInputProfile.translates
        macBookKeyboard.configure(enabled: settings.macBookFnControlSwap && policy.current?.permitsPhysicalNormalization == true,
            eventTapBackend: native, sessionActive: sessionActive)
        macBookKeyboardStatus = macBookKeyboard.status
    }
    func setMacBookFnControlSwap(_ value: Bool) {
        store.update { $0.macBookFnControlSwap = value }; settings = store.settings
        configurationError = store.errorMessage
        guard store.errorMessage == nil else { return }
        if value { ensureMacBookLogin() } else { releaseFeatureLoginIfUnused() }
        publish()
    }
    func refreshMacBookKeyboard() {
        macBookKeyboard.refresh()
        macBookKeyboardStatus = macBookKeyboard.status
    }
    func setScreenshotAutoCopy(_ value: Bool) {
        store.update { $0.screenshotAutoCopy = value }
        settings = store.settings
        configurationError = store.errorMessage
        guard store.errorMessage == nil else { return }
        if value {
            ensureScreenshotLogin()
        } else { releaseFeatureLoginIfUnused() }
        publish()
    }
    func setWindowsKeyModifier(_ value: WindowsKeyModifier) {
        store.update { $0.windowsKeyModifier = value }
        settings = store.settings
        configurationError = store.errorMessage
        guard store.errorMessage == nil else { return }
        publish()
    }
    func setWinRunEnabled(_ value: Bool) {
        store.update { $0.winRunEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setWinSettingsEnabled(_ value: Bool) {
        store.update { $0.winSettingsEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setWinTaskViewEnabled(_ value: Bool) {
        store.update { $0.winTaskViewEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    private func ensureMacBookLogin() {
        let wasRegistered = inputSources.loginIsRegistered
        if inputSources.ensureLoginEnabled(), !wasRegistered {
            UserDefaults.standard.set(true, forKey: macBookManagedLoginKey)
            KeyboardMappingDiagnostics.append("Fn／Ctrl 模式已註冊 App 登入啟動")
        }
    }
    private func releaseFeatureLoginIfUnused() {
        guard !settings.screenshotAutoCopy && !settings.macBookFnControlSwap,
              UserDefaults.standard.bool(forKey: screenshotManagedLoginKey) ||
                UserDefaults.standard.bool(forKey: macBookManagedLoginKey) else { return }
        inputSources.setLoginEnabled(false)
        if !inputSources.loginIsRegistered {
            UserDefaults.standard.removeObject(forKey: screenshotManagedLoginKey)
            UserDefaults.standard.removeObject(forKey: macBookManagedLoginKey)
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
        let generation = policy.current?.generation
        inputSources.readRecentLog { [weak self] text in
            guard let self, self.policy.current?.generation == generation else { return }
            self.sourceLog = text
        }
        sourceStatus = inputSources.status
    }
    func refreshSourceStatistics() {
        sourceStatus = inputSources.status
        sourceMemoryUsage = inputSources.memoryUsageDescription
    }
    private func publish() {
        guard running else { return }
        guard !transitionApplying else { transitionRequested = true; return }
        transitionApplying = true
        defer {
            transitionApplying = false
            if transitionRequested { transitionRequested = false; publish() }
        }
        if settings.inputBackend == .eventTap && hid.hasOwnership { hid.releaseOwnership() }
        if lastAppliedSettings != settings { settingsRevision &+= 1; lastAppliedSettings = settings }
        var input = RuntimePolicyInput()
        input.backend = settings.inputBackend; input.deviceScope = settings.keyboardScope
        input.foreground = context; input.remoteProfile = settings.remoteInputProfile
        input.paused = paused || status.emergencyPaused
        input.manualPassThrough = status.manualPassThrough
        input.secureInput = IsSecureEventInputEnabled()
        input.session = sessionEpoch; input.sessionActive = sessionActive
        input.shortcutEnabled = settings.enabled && registry != nil && configurationError == nil && !installationRecoveryPending
        input.screenshotEnabled = settings.screenshotAutoCopy
        input.settingsRevision = settingsRevision
        input.restartToken = restartToken
        input.accessibility = AXIsProcessTrusted(); input.posting = CGPreflightPostEventAccess()
        input.layoutIdentity = layoutID
        input.layoutSupported = layoutSupported; input.diagnosticsEnabled = diagnosticsEnabled
        input.hidReleasePending = hid.releasePending
        input.nativeRestorePending = macBookKeyboardStatus.restorePending
        let previous = policy.current
        let snapshot = policy.transition(input)
        updateRuntimeTimer()
        guard previous != snapshot else { return }
        var config = EngineConfiguration()
        config.context = context
        config.enabled = snapshot.permitsInput
        config.generation = snapshot.generation
        config.sessionActive = sessionActive
        config.layoutSupported = layoutSupported
        config.diagnostics = diagnosticsEnabled
        config.restartToken = restartToken
        config.keyboardScope = settings.keyboardScope
        config.finderEnabled = settings.finderEnabled
        config.finderPermanentDeleteEnabled = settings.finderPermanentDeleteEnabled
        config.textNavigationEnabled = settings.textNavigationEnabled
        config.altF4Enabled = settings.altF4Enabled
        config.windowsKeyModifier = settings.windowsKeyModifier
        config.macBookFnControlSwap = settings.macBookFnControlSwap
        config.winRunEnabled = settings.winRunEnabled
        config.winSettingsEnabled = settings.winSettingsEnabled
        config.winTaskViewEnabled = settings.winTaskViewEnabled
        config.finderBrightnessEnterEnabled = settings.finderBrightnessEnterEnabled
        config.screenshotEnabled = snapshot.permitsScreenshots
        config.printScreenBehavior = settings.printScreenBehavior
        // Disable old ownership before native mapping restoration or new capture begins.
        var stopped = config; stopped.enabled = false
        engine.update(stopped)
        if previous?.input.backend != snapshot.input.backend { hid.update(stopped, active: false) }
        configureMacBookKeyboard()
        finderPublisher.setEnabled(settings.finderEnabled && snapshot.permitsShortcuts)
        screenshot.applyRuntimePolicy(snapshot, windowsKey: settings.windowsKeyModifier,
                                      printScreen: settings.printScreenBehavior)
        hid.update(config, active: settings.inputBackend == .deviceHID && !macBookKeyboardStatus.restorePending)
        config.enabled = config.enabled && settings.inputBackend == .eventTap
        engine.update(config)
        inputSources.updateRuntimePolicy(snapshot, protection: sourceSuspension(for: context))
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
            $0.keyboardScope = .allKeyboards
        }
        settings = store.settings; configurationError = store.errorMessage
        // Restore native layout before starting HID, which already swaps these physical keys.
        // HID virtual output and uncaptured external keyboards can have different
        // Win modifiers. A session tap cannot identify which device sent S, so
        // do not claim Shift+Alt+S from another keyboard as a screenshot.
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
        publish()
    }
    func setRemoteInputProfile(_ value: RemoteInputProfile) {
        store.update { $0.remoteInputProfile = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setPrintScreenBehavior(_ value: PrintScreenBehavior) {
        store.update { $0.printScreenBehavior = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    func setFinderBrightnessEnterEnabled(_ value: Bool) {
        store.update { $0.finderBrightnessEnterEnabled = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
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
    func setAltF4Enabled(_ value: Bool) {
        store.update { $0.altF4Enabled = value }; settings = store.settings
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
        configurationError = store.errorMessage; refreshLayout(); publish()
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
