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
import IOKit.hid

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
    var bundledInstallerAvailable: Bool { BundledBackendInstaller.available }
    var backgroundInstallationNeeded: Bool { BundledBackendInstaller.needsInstallation }
    @Published private(set) var driverApprovalNotice: String?
    @Published private(set) var driverApprovalLaunched = false
    private let driverActivation = DriverActivationLauncher()
    private var driverRegistered = false
    private(set) var preparedSetupThisLaunch = false
    func requestDriverActivation() {
        if driverVerification != .granted { prepareDriverActivation() }
        openDriverSettings()
    }
    private func prepareDriverActivation() {
        guard !driverApprovalLaunched, !backgroundInstallationNeeded else { return }
        driverApprovalLaunched = true
        driverVerification = .awaitingVerification
        driverNeedsVerification = true
        do {
            try driverActivation.start { [weak self] result in
                guard let self else { return }
                self.driverApprovalLaunched = false
                if result != 0 { self.driverApprovalNotice = "驅動程式準備尚未完成；請依系統提示核准或重新開機，再開啟 App。" }
                self.refreshDriverPermission()
            }
            driverApprovalNotice = "鍵盤驅動已送出核准要求；請在此項的系統設定核准。"
        } catch {
            driverApprovalLaunched = false
            driverApprovalNotice = error.localizedDescription
        }
    }
    @Published var targetApp: ApplicationContext?
    @Published var hidStatus = HIDStatus()
    @Published var screenshotStatus = ScreenshotStatus()
    @Published var macBookKeyboardStatus = MacBookKeyboardMappingStatus()
    @Published var remoteSources: [RemoteSourceStatus] = []
    @Published var calibrationNotice: String?
    @Published private(set) var permissionChecklist = PermissionChecklistState()
    var permissions: PermissionSnapshot { permissionChecklist.verified }
    var keyboardPermissionRestartSuggested: Bool {
        permissions.keyboardControlPartiallyGranted &&
        !permissionChecklist.awaitingVerification.contains(.accessibility) &&
        !permissionChecklist.awaitingVerification.contains(.posting) &&
        !CommandLine.arguments.contains("--permission-relaunch")
    }
    @Published private(set) var permissionRelaunchPending = false
    @Published private(set) var permissionRelaunchNotice: String?
    func restartForPermissions() {
        guard !permissionRelaunchPending else { return }
        do {
            try PermissionRelauncher.start()
            permissionRelaunchPending = true
            // The existing termination handler stops capture, invalidates old
            // screenshot work and restores this App's keyboard mapping.
            NSApp.terminate(nil)
        } catch { permissionRelaunchNotice = error.localizedDescription }
    }
    var inputMonitoringVerification: PermissionVerification {
        let main = permissionChecklist.verification(for: [.listening])
        guard main == .granted, settings.inputBackend == .deviceHID else { return main }
        return hid.hasFreshVerifiedStatus ? PermissionVerification(verifiedGrant: hid.status.permissions) : backgroundInputVerification
    }
    @Published private(set) var backgroundInputVerification = PermissionVerification.unchecked
    @Published private(set) var backgroundInputNotice: String?
    private var backgroundInputCheckPending = false
    @Published private(set) var driverVerification = PermissionVerification.unchecked
    private var driverCheckTask: Task<Void, Never>?
    private var driverNeedsVerification = true
    @Published private(set) var screenshotFolderVerification = PermissionVerification.unchecked
    @Published private(set) var screenshotFolderPath = ScreenshotFolderAccess.currentDirectory().path
    @Published private(set) var screenshotFolderNotice: String?
    private var screenshotFolderCheckTask: Task<Void, Never>?
    private var screenshotFolderCheckID: UUID?
    @Published private(set) var permissionsCheckedAt: Date?
    var finderExtensionEnabled: Bool { permissions.finderExtension }
    private let engine = InputEngine()
    private let remoteRegistry = RemoteSourceRegistry()
    private var lastEngineConfiguration: EngineConfiguration?
    private var calibrationDeadline: Double?
    private let hid = HIDBackendClient()
    private let store = SettingsStore()
    let installationRecoveryPending: Bool
    private let screenshot = ScreenshotManager()
    private let macBookKeyboard = MacBookKeyboardMapper()
    private let finderPublisher = FinderModePublisher()
    private let screenshotFolderRequestKey = "permissions.screenshotFolderRequest.v1"
    private var registry: ApplicationRegistry?
    private var timer: Timer?
    private var timerPlan: RuntimeWakePlan = .stopped
    private var running = false
    private var observers: [NSObjectProtocol] = []
    private var applicationActivationObserver: NSObjectProtocol?
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
        if installationRecoveryPending { return "安裝尚未完成，請依系統提示核准或重新開機後再開啟 App。" }
        if let configurationError { return configurationError }
        if !settings.enabled { return "已停用" }
        if paused || status.emergencyPaused { return "已暫停" }
        if hid.releasePending { return "等待 Helper 安全釋放；新後端尚未啟動" }
        if !permissions.keyboardControlGranted { return "等待鍵盤控制授權（\(KeyboardPermissionRequest.settingsTitle)）" }
        if !permissions.listening { return "等待輸入監控授權（WindowsMacBridge 主 App）" }
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
        if !status.postAccess { return "鍵盤控制授權尚未完成；請重新要求授權" }
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
        if !backgroundInstallationNeeded && !installationRecoveryPending && store.errorMessage == nil &&
            !UserDefaults.standard.bool(forKey: "setup.oneClickPrepared.v1") {
            let builtIn = HIDDeviceInventory.keyboards().contains { $0.builtIn && $0.vendorID == 1452 }
            store.prepareOneClickSetup(hasBuiltInAppleKeyboard: builtIn)
            settings = store.settings; configurationError = store.errorMessage
            if store.errorMessage == nil {
                UserDefaults.standard.set(true, forKey: "setup.oneClickPrepared.v1")
                preparedSetupThisLaunch = true
            }
        }
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
        applicationActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.refreshPermissions()
            }
        }
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
        engine.setScreenshotHandler { [weak self] kind, source in self?.screenshot.requestCapture(kind, source: source) }
        remoteRegistry.onChange = { [weak self] in
            guard let self else { return }
            if self.remoteSources != self.remoteRegistry.statuses { self.remoteSources = self.remoteRegistry.statuses }
            self.publish()
        }
        observe(center, NSWorkspace.didLaunchApplicationNotification) { $0.remoteRegistry.discover() }
        observe(center, NSWorkspace.didTerminateApplicationNotification) { $0.remoteRegistry.maintain([]) }
        hid.onOwnershipChange = { [weak self] in self?.publish() }
        if settings.screenshotAutoCopy { checkScreenshotLogin() }
        refreshPermissions()
        let directory = ScreenshotFolderAccess.currentDirectory()
        if let scope = screenshotFolderRequestScope(directory),
           UserDefaults.standard.string(forKey: screenshotFolderRequestKey) == scope {
            // A previous row-7 operation permits a fresh native check for this
            // exact App/path, so normal launches don't require setup every time.
            verifyScreenshotFolder(directory)
        }
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
        driverActivation.stop()
        driverCheckTask?.cancel(); driverCheckTask = nil
        screenshotFolderCheckTask?.cancel(); screenshotFolderCheckTask = nil
        screenshotFolderCheckID = nil
        remoteRegistry.configure(active: false, preferences: settings.remoteSources)
        remoteRegistry.onChange = nil
        engine.calibrationInbox.cancel()
        finderPublisher.stop()
        timer?.invalidate(); timer = nil; timerPlan = .stopped
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        if let observer = applicationActivationObserver { NotificationCenter.default.removeObserver(observer) }
        applicationActivationObserver = nil
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
        engine.maintain()
        remoteRegistry.maintain(engine.producerInbox.take())
        screenshot.applyInputRouting(remoteRegistry.snapshot)
        if let result = engine.calibrationInbox.take(),
           remoteRegistry.snapshot.producers.contains(where: { $0.identity == result.identity && $0.processID == result.processID && $0.session == result.session }) {
            let transport = remoteSources.first { $0.identity == result.identity }?.transport ?? .generic
            saveRemotePreference(.init(identity: result.identity, semantics: result.semantics, transport: transport, learned: true))
            calibrationNotice = "已保存此來源：\(result.semantics.title)"; calibrationDeadline = nil
        }
        if let deadline = calibrationDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
            engine.calibrationInbox.cancel(); calibrationDeadline = nil; calibrationNotice = "校準逾時；沒有改變來源設定。"
        }
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
            next.processed &+= hidStatus.processed; next.translated &+= hidStatus.translated
            next.maxMicroseconds = max(next.maxMicroseconds, hidStatus.maxMicroseconds)
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
        if (previousAccessibility != next.accessibility || previousListening != next.listenAccess || previousPosting != next.postAccess) &&
            settings.screenshotAutoCopy {
            screenshot.verifyAndRepair(reason: "鍵盤控制／輸入監控權限變更")
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
        if context.processID == ProcessInfo.processInfo.processIdentifier {
            refreshPermissions()
            if screenshotFolderVerification == .granted || screenshotFolderVerification == .denied {
                verifyScreenshotFolder(ScreenshotFolderAccess.currentDirectory())
            }
        }
        if context.processID != ProcessInfo.processInfo.processIdentifier { targetApp = context }
        refreshLayout()
        publish()
    }
    func refreshPermissions(userInitiated: Bool = false, recheckScreenshotFolder: Bool = false) {
        // A source/login notification in the background must not confirm a
        // settings link. Verify once the user returns, or explicitly rechecks.
        if !userInitiated && !permissionChecklist.awaitingVerification.isEmpty && !NSApp.isActive { return }
        let previous = permissionChecklist.verified
        let current = PermissionStatus.current()
        var next = permissionChecklist
        next.verify(current)
        if permissionChecklist != next { permissionChecklist = next }
        permissionsCheckedAt = Date()
        let directory = ScreenshotFolderAccess.currentDirectory()
        let folderChanged = screenshotFolderPath != directory.path
        if folderChanged {
            screenshotFolderPath = directory.path
            screenshotFolderVerification = .unchecked
            screenshotFolderNotice = nil
            UserDefaults.standard.removeObject(forKey: screenshotFolderRequestKey)
        }
        // Folder reads can themselves prompt for access. Opening an unrelated
        // permission row must not request Desktop/Documents/Downloads access.
        // Only row 7 starts that I/O; later foreground checks can recheck it.
        if recheckScreenshotFolder && (screenshotFolderVerification == .granted || screenshotFolderVerification == .denied) {
            verifyScreenshotFolder(directory)
        }
        if userInitiated || driverNeedsVerification || (NSApp.isActive && settingsPage == .permissions) {
            refreshDriverPermission()
            if settings.inputBackend == .deviceHID && !backgroundInstallationNeeded { refreshBackgroundInputPermission() }
        }
        if running && (previous != current || folderChanged) {
            publish()
            engine.maintain()
            if settings.screenshotAutoCopy {
                screenshot.verifyAndRepair(reason: "授權狀態重新確認")
            }
        }
    }
    private func refreshDriverPermission() {
        guard driverCheckTask == nil else { driverNeedsVerification = true; return }
        driverNeedsVerification = false
        driverVerification = .awaitingVerification
        driverCheckTask = Task { [weak self] in
            let result = await DriverPermissionCheck.read()
            guard !Task.isCancelled, let self else { return }
            self.driverCheckTask = nil
            if self.driverNeedsVerification { self.refreshDriverPermission() }
            else {
                self.driverVerification = PermissionVerification(verifiedGrant: result?.granted)
                self.driverRegistered = result?.registered ?? false
                if result?.granted == true { self.driverApprovalNotice = nil }
            }
        }
    }
    func openDriverSettings() {
        driverVerification = .awaitingVerification
        driverNeedsVerification = true
        if #available(macOS 15, *), let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.driver_extension.extension-point"),
           NSWorkspace.shared.open(url) { return }
        inputSources.openLoginSettings()
    }
    func openScreenshotFolderSettings() {
        // Request the configured folder through native I/O. No path selection.
        verifyScreenshotFolder(ScreenshotFolderAccess.currentDirectory())
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
    private func screenshotFolderRequestScope(_ directory: URL) -> String? {
        PermissionStatus.codeIdentity.map { $0 + "\n" + directory.resolvingSymlinksInPath().standardizedFileURL.path }
    }
    private func verifyScreenshotFolder(_ directory: URL) {
        // Directory I/O can wait on a volume. Keep at most one worker even if
        // the user repeatedly checks, cancels, or changes the screenshot path.
        guard screenshotFolderCheckTask == nil else { return }
        let id = UUID(); screenshotFolderCheckID = id
        screenshotFolderVerification = .awaitingVerification
        screenshotFolderNotice = nil
        publish()
        screenshotFolderCheckTask = Task { [weak self] in
            let readable = await Task.detached(priority: .utility) {
                return ScreenshotFolderAccess.canRead(directory)
            }.value
            guard !Task.isCancelled, let self, self.screenshotFolderCheckID == id else { return }
            self.screenshotFolderCheckTask = nil
            guard directory.resolvingSymlinksInPath().standardizedFileURL == ScreenshotFolderAccess.currentDirectory() else {
                self.screenshotFolderVerification = .unchecked
                self.publish()
                return
            }
            self.screenshotFolderPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
            self.screenshotFolderVerification = PermissionVerification(verifiedGrant: readable)
            if readable, let scope = self.screenshotFolderRequestScope(directory) {
                UserDefaults.standard.set(scope, forKey: self.screenshotFolderRequestKey)
            } else {
                UserDefaults.standard.removeObject(forKey: self.screenshotFolderRequestKey)
            }
            self.publish()
            if readable, self.settings.screenshotAutoCopy {
                self.screenshot.verifyAndRepair(reason: "截圖資料夾存取已確認")
            }
        }
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
    func requestLoginItem() {
        inputSources.setLoginEnabled(true)
        refreshPermissions(userInitiated: true)
        openPermissionSettings(.loginItem)
    }
    private func sourceSuspension(for app: ApplicationContext) -> InputSourceSuspension? {
        if installationRecoveryPending { return .protectedApplication }
        if IsSecureEventInputEnabled() { return .protectedApplication }
        return InputSourcePolicy.suspension(context: app,
            isHostApp: app.processID == ProcessInfo.processInfo.processIdentifier,
            paused: paused || status.emergencyPaused || status.manualPassThrough, sessionActive: sessionActive)
    }
    private func setSuspended(_ reason: SuspensionReason, _ suspended: Bool) {
        if suspended { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        sessionEpoch &+= 1
        if !suspended && settings.screenshotAutoCopy {
            screenshot.verifyAndRepair(reason: "Session 恢復")
        }
        publish()
    }
    private func configureMacBookKeyboard(configuration: EngineConfiguration) {
        let native = configuration.usesNativePhysicalMapping
        macBookKeyboard.configure(enabled: settings.macBookFnControlSwap && permissions.loginItem &&
            policy.current?.permitsPhysicalNormalization == true,
            eventTapBackend: native, sessionActive: sessionActive)
        macBookKeyboardStatus = macBookKeyboard.status
    }
    func setMacBookFnControlSwap(_ value: Bool) {
        store.update { $0.macBookFnControlSwap = value }; settings = store.settings
        configurationError = store.errorMessage
        guard store.errorMessage == nil else { return }
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
            checkScreenshotLogin()
        }
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
    private func checkScreenshotLogin() {
        // Runtime checks and feature toggles never register/unregister a
        // different permission. Row 4 owns the login authorization action.
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
        checkScreenshotLogin()
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
        if lastAppliedSettings != settings.physicalPolicySettings { settingsRevision &+= 1; lastAppliedSettings = settings.physicalPolicySettings }
        var input = RuntimePolicyInput()
        input.backend = settings.inputBackend; input.deviceScope = settings.keyboardScope
        input.foreground = context
        input.paused = paused || status.emergencyPaused
        input.manualPassThrough = status.manualPassThrough
        input.secureInput = IsSecureEventInputEnabled()
        input.session = sessionEpoch; input.sessionActive = sessionActive
        input.shortcutEnabled = settings.enabled && registry != nil && configurationError == nil && !installationRecoveryPending
        // Do not touch the user's protected screenshot directory while they
        // are authorizing a different row. Row 7 enables screenshot work only
        // after a genuine directory read succeeds.
        input.screenshotEnabled = settings.screenshotAutoCopy && screenshotFolderVerification == .granted
        input.settingsRevision = settingsRevision
        input.restartToken = restartToken
        input.accessibility = AXIsProcessTrusted(); input.posting = CGPreflightPostEventAccess()
        input.loginItemEnabled = permissions.loginItem
        input.layoutIdentity = layoutID
        input.layoutSupported = layoutSupported; input.diagnosticsEnabled = diagnosticsEnabled
        input.hidReleasePending = hid.releasePending
        input.nativeRestorePending = macBookKeyboardStatus.restorePending
        let previous = policy.current
        let snapshot = policy.transition(input)
        remoteRegistry.configure(active: snapshot.permitsShortcuts, preferences: settings.remoteSources)
        updateRuntimeTimer()
        if previous == snapshot {
            if var config = lastEngineConfiguration, config.inputRouting != remoteRegistry.snapshot || config.deviceInputs != settings.deviceInputs {
                let deviceChanged = config.deviceInputs != settings.deviceInputs
                config.inputRouting = remoteRegistry.snapshot; config.deviceInputs = settings.deviceInputs; lastEngineConfiguration = config
                if deviceChanged { hid.update(config, active: settings.inputBackend == .deviceHID && !macBookKeyboardStatus.restorePending) }
                screenshot.applyPhysicalPreferences(config.deviceInputs)
                screenshot.applyInputRouting(config.inputRouting); engine.update(config)
            }
            return
        }
        engine.calibrationInbox.cancel(); calibrationDeadline = nil
        var config = EngineConfiguration()
        config.context = context
        config.enabled = snapshot.permitsInput
        config.generation = snapshot.generation
        config.runtimePolicy = snapshot
        config.physicalBackend = settings.inputBackend
        config.inputRouting = remoteRegistry.snapshot
        config.deviceInputs = settings.deviceInputs
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
        // The rule engine checks the receiving App mode. Keep the feature flag
        // stable across App-only changes; ScreenshotManager still applies the
        // stricter runtime policy and cancels old jobs on every generation.
        config.screenshotEnabled = input.screenshotEnabled && snapshot.permitsShortcuts
        config.printScreenBehavior = settings.printScreenBehavior
        // Disable old ownership before native mapping restoration or new capture begins.
        var stopped = config; stopped.enabled = false
        if lastEngineConfiguration.map({ config.preservesModifiers(from: $0) }) != true {
            engine.update(stopped)
        }
        if previous?.input.backend != snapshot.input.backend { hid.update(stopped, active: false) }
        configureMacBookKeyboard(configuration: config)
        finderPublisher.setEnabled(settings.finderEnabled && snapshot.permitsShortcuts)
        screenshot.applyRuntimePolicy(snapshot, windowsKey: settings.windowsKeyModifier,
                                      printScreen: settings.printScreenBehavior)
        screenshot.applyInputRouting(config.inputRouting)
        screenshot.applyPhysicalPreferences(config.deviceInputs)
        hid.update(config, active: settings.inputBackend == .deviceHID && !macBookKeyboardStatus.restorePending)
        // HID transports App-sensitive chords raw; annotated delivery supplies
        // receiving-App semantics. Classified remote sources keep separate ledgers.
        lastEngineConfiguration = config
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
    private func refreshBackgroundInputPermission() {
        guard !backgroundInputCheckPending else { return }
        backgroundInputCheckPending = true
        backgroundInputVerification = .awaitingVerification
        hid.checkInputAccess { [weak self] grant in
            guard let self else { return }
            self.backgroundInputCheckPending = false
            self.backgroundInputVerification = PermissionVerification(verifiedGrant: grant)
            self.backgroundInputNotice = grant == nil ? "背景元件尚未連線，請關閉並重新開啟 App。" : nil
        }
    }
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
    func setPrintScreenBehavior(_ value: PrintScreenBehavior) {
        store.update { $0.printScreenBehavior = value }; settings = store.settings
        configurationError = store.errorMessage; publish()
    }
    private func saveRemotePreference(_ preference: RemoteSourcePreference) {
        store.update {
            if let i = $0.remoteSources.firstIndex(where: { $0.identity == preference.identity }) { $0.remoteSources[i] = preference }
            else if $0.remoteSources.count < 32 { $0.remoteSources.append(preference) }
        }
        settings = store.settings; configurationError = store.errorMessage; publish()
    }
    func setRemoteSemantics(_ semantics: RemoteSemantics, source: RemoteSourceStatus) {
        engine.calibrationInbox.cancel(); calibrationDeadline = nil
        saveRemotePreference(.init(identity: source.identity, semantics: semantics, transport: source.transport))
    }
    func setRemoteTransport(_ transport: RemoteTransport, source: RemoteSourceStatus) {
        engine.calibrationInbox.cancel(); calibrationDeadline = nil
        saveRemotePreference(.init(identity: source.identity, semantics: source.semantics, transport: transport, learned: source.learned))
    }
    func calibrateRemote(_ source: RemoteSourceStatus) {
        guard policy.current?.permitsShortcuts == true else { return }
        engine.calibrationInbox.arm(identity: source.identity, processID: source.processID, session: source.session)
        calibrationDeadline = ProcessInfo.processInfo.systemUptime + 60
        calibrationNotice = "請在此遠端電腦按一次 Ctrl+C。只辨識這個測試組合，60 秒內有效。"
    }
    func setDeviceExperience(_ experience: DeviceExperience, identity: String) {
        guard (settings.deviceInputs.first { $0.identity == identity }?.experience ?? .windows) != experience else { return }
        store.update {
            if let i = $0.deviceInputs.firstIndex(where: { $0.identity == identity }) { $0.deviceInputs[i].experience = experience }
            else if $0.deviceInputs.count < 16 { $0.deviceInputs.append(.init(identity: identity, experience: experience)) }
        }
        settings = store.settings; configurationError = store.errorMessage; publish()
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
        refreshPermissions(userInitiated: true)
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
        _ = KeyboardPermissionRequest.perform(read: { PermissionStatus.current() })
        refreshPermissions(userInitiated: true)
        publish()
    }
    func requestListening() {
        // Exactly one request for this App's Input Monitoring permission.
        if settings.inputBackend == .deviceHID {
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
                _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            }
        } else if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        refreshPermissions(userInitiated: true)
    }
    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
