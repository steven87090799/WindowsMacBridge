// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import AppKit
import Carbon
import CoreFoundation
import Foundation
import InputSourceCore
import BridgeCore

private final class GuardNotificationOwner {
    weak var controller: GuardController?
    init(_ controller: GuardController) { self.controller = controller }
}
final class GuardController {
    private enum EnvironmentSuspensionReason: Hashable {
        case hostPolicy
        case systemSleep
        case screensSleep
        case inactiveSession
    }

    private enum Configuration {
        static let maximumSelectionAttempts = 3
        static let verificationDelayMilliseconds = 400
        static let startupRetryDelaysMilliseconds = [1_000, 2_000, 4_000]
        static let secureInputPollDelaysSeconds = [2, 2, 2, 5, 5, 10, 10, 30]
        static let automaticCorrectionWindow: TimeInterval = 60
        static let automaticCorrectionLimit = 10
        static let automaticCorrectionCooldown: TimeInterval = 30
    }

    let inputSources = InputSourceManager()
    var selectionAllowed: () -> Bool = { false }
    var onStateChange: (() -> Void)?
    var onIssue: ((String) -> Void)?

    private var machine: GuardStateMachine
    private var observer: UnsafeMutableRawPointer?
    private var selectedSourceObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var environmentObservers: [NSObjectProtocol] = []
    private var environmentSuspensionReasons = Set<EnvironmentSuspensionReason>()
    private var workspaceObserversInstalled = false
    private var shouldReconcileAfterWake = false

    private var reconciliationWork: DispatchWorkItem?
    private var startupWork: DispatchWorkItem?
    private var verificationWork: DispatchWorkItem?
    private var correctionCooldownWork: DispatchWorkItem?

    private var secureRecoveryTimer: DispatchSourceTimer?
    private var secureRecoveryPollIndex = 0
    private var pendingExplicitSelection: DesiredInputSource?

    private var pendingInternalSourceID: String?
    private var pendingSelectionWasAutomatic = false
    private var isWaitingForSecureInputToEnd = false
    private var secureInputIsBlockingRecorded = false
    private var didReportRetryExhaustion = false
    private var startupRetryCount = 0
    private var isStarted = false
    private var workEpoch: UInt64 = 0
    private let notifications = DeferredSignalMailbox()

    private var automaticCorrectionTimestamps: [Date] = []
    private var correctionCooldownUntil: Date?
    private var detectionPause = AppSettings.detectionPause
    private var pauseRecoveryWork: DispatchWorkItem?
    private var pauseGeneration = 0
    private var lastObservedIdentifier: String?
    /// Enabled-source changes that arrived while work was suspended or cancelled.
    /// A host resume rediscovers (a full TIS enumeration) only when this is set
    /// or the guard is enabled, not on every protected-App round trip.
    private var discoveryStale = false
    private(set) var preservedSourceIdentifier = AppSettings.preservedSourceIdentifier

    init() {
        machine = GuardStateMachine(
            isEnabled: AppSettings.guardEnabled,
            debounceMilliseconds: AppSettings.debounceMilliseconds,
            maximumSelectionAttempts: Configuration.maximumSelectionAttempts
        )
    }

    deinit { stop() }

    var desired: DesiredInputSource { machine.desired }
    var isEnabled: Bool { machine.isEnabled }
    var selectionInProgress: Bool { pendingInternalSourceID != nil }
    var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }
    var isDetectionPaused: Bool { detectionPause.isActive(at: Date()) }
    var detectionPauseUntil: Date? { detectionPause.until }
    var detectionPauseIndefinite: Bool { detectionPause.indefinite }
    private var automaticReconciliationAllowed: Bool {
        isStarted && isEnabled && !isEnvironmentSuspended && !isDetectionPaused &&
            machine.preservedSelection == nil && selectionAllowed()
    }

    private var isEnvironmentSuspended: Bool {
        !environmentSuspensionReasons.isEmpty
    }

    private var isCorrectionCoolingDown: Bool {
        guard let correctionCooldownUntil else { return false }
        return correctionCooldownUntil > Date()
    }

    var statusText: String {
        if isEnvironmentSuspended { return "◌ 系統待機中" }
        if !isEnabled { return "○ 輸入法守護已關閉" }
        if isDetectionPaused { return "◌ 自動偵測已暫停" }
        if preservedSourceIdentifier != nil { return "● 手動切換已保留" }
        if isCorrectionCoolingDown { return "◌ 偵測到輸入源衝突，暫時冷卻" }
        if inputSources.discovery.traditional == nil { return "⚠ 找不到唯音-繁" }

        let currentIdentifier = inputSources.currentSource().identifier
        if desired == .vChewing,
           sourceDiffersFromDesired(currentIdentifier),
           isSecureInputEnabled {
            return "◌ 等待切換唯音（安全輸入中）"
        }

        return switch desired {
        case .vChewing: "● 唯音繁體已選擇"
        case .abc: "● ABC 已選擇"
        }
    }

    var issueDescription: String? {
        if inputSources.discovery.traditional == nil {
            return "找不到已安裝的唯音繁體輸入模式。請安裝或啟用唯音-繁，再從選單選擇「重新啟用 Guard」。"
        }
        if inputSources.discovery.abc == nil {
            return "找不到 macOS ABC 輸入來源。請到「系統設定」>「鍵盤」>「文字輸入」新增 ABC。"
        }
        if let target = targetSource, (!target.isEnabled || !target.isSelectable) {
            return "\(target.summary)。請在「系統設定」>「鍵盤」>「文字輸入」啟用此輸入來源。"
        }
        return nil
    }

    private var targetSource: InputSourceInfo? {
        switch machine.desired {
        case .vChewing: inputSources.discovery.traditional
        case .abc: inputSources.discovery.abc
        }
    }

    // The host owns profile/pause policy. Suspension cancels pending selections,
    // verification and Secure Input retries before another application receives input.
    func setHostSuspended(_ suspended: Bool) {
        if suspended {
            suspendForEnvironment(.hostPolicy, reason: "Unified app policy")
        } else {
            resumeFromEnvironment(.hostPolicy, reason: "Unified app policy resumed")
        }
    }

    func prepareForLaunch() {
        guard !workspaceObserversInstalled else { return }
        installWorkspaceObservers()
        workspaceObserversInstalled = true
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        prepareForLaunch()

        FileLogger.shared.log("Guard started; respecting the current input source")
        installTISObservers()
        _ = inputSources.rediscover(); discoveryStale = false
        preserveCurrentSelection(record: false)
        schedulePauseRecovery()
        startupRetryCount = 0
        scheduleStartupReconciliation(after: AppSettings.startupDelayMilliseconds)
        onStateChange?()
    }

    func stop() {
        guard isStarted || workspaceObserversInstalled else { return }
        isStarted = false

        if let observer {
            let center = CFNotificationCenterGetDistributedCenter()
            CFNotificationCenterRemoveObserver(center, observer, nil, nil)
            Unmanaged<GuardNotificationOwner>.fromOpaque(observer).release()
            self.observer = nil
        }

        removeWorkspaceObservers()
        cancelScheduledWork()
        cancelCorrectionCooldownWork()
        pauseGeneration += 1
        pauseRecoveryWork?.cancel(); pauseRecoveryWork = nil
        stopSecureRecoveryTimer()
        pendingExplicitSelection = nil
        // A later start must not inherit a selection gate or a stale observation.
        pendingInternalSourceID = nil; pendingSelectionWasAutomatic = false
        lastObservedIdentifier = nil; discoveryStale = true
        environmentSuspensionReasons.removeAll()
        shouldReconcileAfterWake = false
        automaticCorrectionTimestamps.removeAll()
        correctionCooldownUntil = nil

        FileLogger.shared.log("Guard stopped")
    }

    func invalidateHostWork() {
        cancelScheduledWork(); stopSecureRecoveryTimer(); cancelCorrectionCooldownWork()
        pendingInternalSourceID = nil; pendingExplicitSelection = nil; pendingSelectionWasAutomatic = false
    }

    func request(_ source: DesiredInputSource) {
        machine.request(source)
        preservedSourceIdentifier = nil
        AppSettings.setPreservedSourceIdentifier(nil)
        machine.setDebounce(milliseconds: AppSettings.debounceMilliseconds)
        FileLogger.shared.log("User requested \(source == .vChewing ? "vChewing Traditional" : "ABC")")

        cancelScheduledWork()
        stopSecureRecoveryTimer()
        pendingExplicitSelection = nil
        didReportRetryExhaustion = false
        pendingInternalSourceID = nil

        onStateChange?()
        selectDesiredSource(isExplicitUserRequest: true)
    }

    func toggleDesiredSource() {
        let source = machine.toggleDesiredSource()
        request(source)
    }

    func pauseDetection(_ duration: GuardPauseDuration, now: Date = Date()) {
        detectionPause = GuardDetectionPause(duration: duration, now: now)
        AppSettings.setDetectionPause(detectionPause)
        preserveCurrentSelection(record: false)
        cancelScheduledWork()
        resetCorrectionCircuitBreaker()
        stopSecureRecoveryTimer()
        pendingExplicitSelection = nil
        pendingInternalSourceID = nil
        pendingSelectionWasAutomatic = false
        machine.selectionSucceeded()
        schedulePauseRecovery()
        FileLogger.shared.log("Automatic detection paused: \(duration.title)")
        onStateChange?()
    }

    func resumeDetection() {
        detectionPause = GuardDetectionPause()
        AppSettings.setDetectionPause(detectionPause)
        pauseGeneration += 1
        pauseRecoveryWork?.cancel(); pauseRecoveryWork = nil
        if pendingInternalSourceID == nil, pendingExplicitSelection == nil {
            preserveCurrentSelection(record: false)
        }
        FileLogger.shared.log("Automatic detection resumed; keeping the current input source")
        onStateChange?()
    }

    private func schedulePauseRecovery() {
        pauseGeneration += 1
        pauseRecoveryWork?.cancel(); pauseRecoveryWork = nil
        guard isStarted else { return }
        guard isDetectionPaused else {
            if detectionPause.until != nil { resumeDetection() }
            return
        }
        guard !detectionPause.indefinite, let until = detectionPause.until else { return }
        let generation = pauseGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted, self.pauseGeneration == generation else { return }
            self.pauseRecoveryWork = nil
            if self.isDetectionPaused { self.schedulePauseRecovery() }
            else { self.resumeDetection() }
        }
        pauseRecoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until.timeIntervalSinceNow), execute: work)
    }

    private func preserveCurrentSelection(record: Bool) {
        guard pendingInternalSourceID == nil, pendingExplicitSelection == nil,
              let identifier = inputSources.currentIdentifier else { return }
        preserveExternalSelection(identifier, record: record)
    }

    private func preserveExternalSelection(_ identifier: String, record: Bool) {
        let changed = identifier != lastObservedIdentifier
        let observed = InputSourceManager.observedSource(identifier: identifier, discovery: inputSources.discovery)
        machine.preserveExternalSelection(observed)
        lastObservedIdentifier = identifier
        if preservedSourceIdentifier != identifier {
            preservedSourceIdentifier = identifier
            AppSettings.setPreservedSourceIdentifier(identifier)
        }
        cancelScheduledWork()
        resetCorrectionCircuitBreaker()
        stopSecureRecoveryTimer()
        pendingExplicitSelection = nil
        pendingInternalSourceID = nil
        pendingSelectionWasAutomatic = false
        startupRetryCount = 0
        didReportRetryExhaustion = false
        if record, changed {
            DiagnosticMetrics.shared.recordPreservedExternalSelection()
            FileLogger.shared.log("External input source selection preserved: \(identifier)")
        }
    }

    func setGuardEnabled(_ enabled: Bool) {
        AppSettings.setGuardEnabled(enabled)
        machine.setEnabled(enabled)
        FileLogger.shared.log("Guard \(enabled ? "resumed" : "paused")")

        cancelScheduledWork()
        stopSecureRecoveryTimer()
        pendingExplicitSelection = nil
        didReportRetryExhaustion = false
        pendingInternalSourceID = nil
        startupRetryCount = 0
        resetCorrectionCircuitBreaker()
        preserveCurrentSelection(record: false)

        onStateChange?()
        if enabled {
            refreshAndReconcile(reason: "Guard resumed")
        }
    }

    func debounceSettingChanged() {
        machine.setDebounce(milliseconds: AppSettings.debounceMilliseconds)
        guard automaticReconciliationAllowed else { return }

        let currentIdentifier = inputSources.currentSource().identifier
        guard sourceDiffersFromDesired(currentIdentifier) else { return }
        scheduleReconciliation(after: machine.debounceMilliseconds)
    }

    func refreshAndReconcile(reason: String, forceDiscovery: Bool = false) {
        guard !isEnvironmentSuspended else { return }

        if isEnabled || forceDiscovery { FileLogger.shared.log(reason) }
        if isEnabled || forceDiscovery || discoveryStale {
            _ = inputSources.rediscover(); discoveryStale = false
        }

        // A refresh or wake must not turn a manually selected source back into
        // an automatic correction. TIS does not report who initiated a switch.
        preserveCurrentSelection(record: false)
        schedulePauseRecovery()
        guard automaticReconciliationAllowed else {
            onStateChange?()
            return
        }

        if targetSource == nil {
            scheduleStartupReconciliation(after: 1_000)
            onStateChange?()
            return
        }

        let currentIdentifier = inputSources.currentSource().identifier
        let response = machine.observe(
            InputSourceManager.observedSource(identifier: currentIdentifier, discovery: inputSources.discovery),
            isInternalSwitch: false
        )
        handle(response)
        onStateChange?()
    }

    var diagnostics: String {
        let discovery = inputSources.discovery
        let current = inputSources.currentSource()
        let traditional = discovery.traditional?.summary ?? "未找到"
        let abc = discovery.abc?.summary ?? "未找到"
        let vCandidates = discovery.vChewingCandidates.map(\.summary).joined(separator: "\n  ")
        let cooldown: String
        if let until = correctionCooldownUntil, until > Date() {
            cooldown = String(format: "冷卻中，約 %.0f 秒後恢復", until.timeIntervalSinceNow)
        } else {
            cooldown = "未啟用"
        }

        return [
            "WindowsMacBridge 輸入法模組 版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Guard：\(isEnabled ? "啟用" : "暫停")；目標：\(desired == .vChewing ? "唯音-繁" : "ABC")",
            "自動偵測暫停：\(isDetectionPaused ? (detectionPause.indefinite ? "直到手動恢復" : detectionPause.until?.description ?? "暫停") : "無")",
            "保留的輸入來源：\(preservedSourceIdentifier ?? "無；可執行明確切換")",
            "目前輸入源：\(current.identifier ?? "（無法讀取）")（\(current.localizedName ?? "無名稱")）",
            "唯音-繁：\(traditional)",
            "ABC：\(abc)",
            "Secure Input：\(isSecureInputEnabled ? "目前啟用" : "目前未啟用")",
            "切換衝突保護：\(cooldown)",
            "診斷計數器：",
            DiagnosticMetrics.shared.summary(),
            "登入時啟動：\(LoginItemManager.statusDescription)",
            "全域快捷鍵：\(AppSettings.hotkeyPreset.title)",
            "唯音候選：\(vCandidates.isEmpty ? "無" : "\n  \(vCandidates)")",
            "日誌：\(FileLogger.shared.path)",
        ].joined(separator: "\n")
    }

    private func sourceDiffersFromDesired(_ identifier: String?) -> Bool {
        switch machine.desired {
        case .vChewing:
            identifier != inputSources.traditionalIdentifier
        case .abc:
            identifier != inputSources.abcIdentifier
        }
    }

    private func installTISObservers() {
        let center = CFNotificationCenterGetDistributedCenter()
        let pointer = Unmanaged.passRetained(GuardNotificationOwner(self)).toOpaque()
        observer = pointer

        CFNotificationCenterAddObserver(
            center,
            pointer,
            Self.handleDistributedNotification,
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center,
            pointer,
            Self.handleDistributedNotification,
            kTISNotifyEnabledKeyboardInputSourcesChanged,
            nil,
            .deliverImmediately
        )
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        selectedSourceObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isWaitingForSecureInputToEnd else { return }
            self.checkForSecureInputEnd()
            if self.isWaitingForSecureInputToEnd {
                self.ensureSecureRecoveryTimer()
            }
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.startupRetryCount = 0
            self.shouldReconcileAfterWake = true
            self.resumeFromEnvironment(.systemSleep, reason: "System woke; re-discovering input sources")
        }

        environmentObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForEnvironment(.systemSleep, reason: "System is going to sleep")
        })

        environmentObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForEnvironment(.screensSleep, reason: "Screens went to sleep")
        })

        environmentObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeFromEnvironment(.screensSleep, reason: "Screens woke; re-discovering input sources")
        })

        environmentObservers.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForEnvironment(.inactiveSession, reason: "User session switched out")
        })

        environmentObservers.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeFromEnvironment(.inactiveSession, reason: "User session resumed; re-discovering input sources")
        })

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isWaitingForSecureInputToEnd else { return }
            self.checkForSecureInputEnd()
            if self.isWaitingForSecureInputToEnd {
                self.ensureSecureRecoveryTimer()
            }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        if let selectedSourceObserver {
            center.removeObserver(selectedSourceObserver)
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
        if let wakeObserver {
            center.removeObserver(wakeObserver)
        }
        for environmentObserver in environmentObservers {
            center.removeObserver(environmentObserver)
        }

        environmentObservers.removeAll()
        selectedSourceObserver = nil
        appActiveObserver = nil
        wakeObserver = nil
        workspaceObserversInstalled = false
    }

    private static let handleDistributedNotification: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer else { return }
        guard let controller = Unmanaged<GuardNotificationOwner>.fromOpaque(observer).takeUnretainedValue().controller else { return }

        let enabledChanged = name.map { ($0.rawValue as String) == (kTISNotifyEnabledKeyboardInputSourcesChanged as String) } ?? false
        guard controller.notifications.offer(enabledChanged ? 2 : 1) else { return }
        DispatchQueue.main.async { [weak controller] in
            guard let controller else { return }
            let signals = controller.notifications.take()
            guard controller.isStarted, !controller.isEnvironmentSuspended else {
                if signals & 2 != 0 { controller.discoveryStale = true }
                return
            }
            if signals & 2 != 0 { controller.handleEnabledSourcesChange() }
            if signals & 1 != 0 { controller.handleSelectedSourceChange() }
        }
    }

    private func handleEnabledSourcesChange() {
        guard isStarted, !isEnvironmentSuspended else { return }

        FileLogger.shared.log("Enabled input sources changed; re-discovering")
        startupRetryCount = 0
        _ = inputSources.rediscover(); discoveryStale = false
        preserveCurrentSelection(record: false)

        if automaticReconciliationAllowed {
            if targetSource == nil {
                scheduleStartupReconciliation(after: 1_000)
            } else {
                reconcileObservedSource()
            }
        }
        onStateChange?()
    }

    private func handleSelectedSourceChange() {
        guard isStarted else { return }

        let currentIdentifier = inputSources.currentSource().identifier
        let decision = SourceNotificationDecision.evaluate(
            current: currentIdentifier, pendingTarget: pendingInternalSourceID,
            waitingForExplicitSelection: pendingExplicitSelection != nil, lastObserved: lastObservedIdentifier
        )

        if decision == .ownSelectionConfirmed {
            let wasAutomatic = pendingSelectionWasAutomatic
            let restoredVChewing = currentIdentifier == inputSources.traditionalIdentifier
            DiagnosticMetrics.shared.recordSelectionSuccess(
                automatic: wasAutomatic,
                restoredVChewing: restoredVChewing
            )
            pendingInternalSourceID = nil
            pendingSelectionWasAutomatic = false
            machine.selectionSucceeded()
            lastObservedIdentifier = currentIdentifier
            didReportRetryExhaustion = false
            pendingExplicitSelection = nil
            cancelReconciliationWork()
            cancelVerificationWork()

            if currentIdentifier == inputSources.traditionalIdentifier || currentIdentifier == inputSources.abcIdentifier {
                FileLogger.shared.log("Guard's own TIS selection confirmed: \(currentIdentifier ?? "")")
            }

            if !isSecureInputEnabled {
                stopSecureRecoveryTimer()
            }
            onStateChange?()
            return
        }

        // A notification for the previous source can also be a user switching
        // back before our own confirmation arrives. Cancel conservatively when
        // it differs from an in-flight target, even if the source is unchanged.
        guard decision == .preserveExternalSelection, let currentIdentifier else { return }

        if pendingInternalSourceID != nil {
            FileLogger.shared.log("Input source changed before Guard's selection completed")
            DiagnosticMetrics.shared.recordFailedSelection()
            pendingInternalSourceID = nil
            pendingSelectionWasAutomatic = false
            cancelVerificationWork()
        }

        preserveExternalSelection(currentIdentifier, record: isEnabled)
        onStateChange?()
    }

    private func reconcileObservedSource() {
        guard automaticReconciliationAllowed else { return }
        let currentIdentifier = inputSources.currentSource().identifier
        let observed = InputSourceManager.observedSource(
            identifier: currentIdentifier,
            discovery: inputSources.discovery
        )
        handle(machine.observe(observed, isInternalSwitch: false))
    }

    private func handle(_ response: SourceChangeResponse) {
        switch response {
        case .ignored:
            cancelReconciliationWork()

        case .alreadySatisfied:
            cancelReconciliationWork()
            cancelVerificationWork()
            stopSecureRecoveryTimer()
            pendingExplicitSelection = nil
            didReportRetryExhaustion = false

        case let .scheduleDebounce(milliseconds):
            didReportRetryExhaustion = false
            scheduleReconciliation(after: milliseconds)
        }
    }

    private func scheduleStartupReconciliation(after milliseconds: Int) {
        guard automaticReconciliationAllowed else { return }
        startupWork?.cancel()
        let epoch = workEpoch
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.workEpoch == epoch else { return }
            self.performStartupReconciliation()
        }
        startupWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(max(0, milliseconds)),
            execute: work
        )
    }

    private func performStartupReconciliation() {
        startupWork = nil
        guard automaticReconciliationAllowed else { return }

        _ = inputSources.rediscover()
        guard let targetSource else {
            if startupRetryCount < Configuration.startupRetryDelaysMilliseconds.count {
                let delay = Configuration.startupRetryDelaysMilliseconds[startupRetryCount]
                startupRetryCount += 1
                FileLogger.shared.log(
                    "vChewing not ready; bounded discovery retry \(startupRetryCount)/\(Configuration.startupRetryDelaysMilliseconds.count) in \(delay)ms"
                )
                scheduleStartupReconciliation(after: delay)
            } else {
                FileLogger.shared.log(
                    "vChewing discovery retries exhausted; waiting for an input-source change or wake"
                )
                onIssue?(issueDescription ?? "找不到唯音-繁。")
            }
            onStateChange?()
            return
        }

        startupRetryCount = 0

        guard targetSource.isEnabled && targetSource.isSelectable else {
            onIssue?(issueDescription ?? "唯音-繁目前不可選擇。")
            onStateChange?()
            return
        }

        reconcileObservedSource()
        onStateChange?()
    }

    private func scheduleReconciliation(after milliseconds: Int) {
        guard automaticReconciliationAllowed else { return }
        cancelReconciliationWork()
        let epoch = workEpoch
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.workEpoch == epoch else { return }
            self.attemptReconciliation()
        }
        reconciliationWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(max(0, milliseconds)),
            execute: work
        )
    }

    private func attemptReconciliation() {
        reconciliationWork = nil
        guard automaticReconciliationAllowed else { return }

        let currentIdentifier = inputSources.currentSource().identifier
        guard isEnabled, sourceDiffersFromDesired(currentIdentifier) else {
            if !sourceDiffersFromDesired(currentIdentifier) {
                machine.selectionSucceeded()
            }
            onStateChange?()
            return
        }

        selectDesiredSource(isExplicitUserRequest: false)
    }

    private func selectDesiredSource(isExplicitUserRequest: Bool) {
        guard selectionAllowed() else { return }
        guard !isEnvironmentSuspended else { return }
        if !isExplicitUserRequest, !automaticReconciliationAllowed { return }

        if targetSource == nil || discoveryStale {
            _ = inputSources.rediscover(); discoveryStale = false
        }

        guard let target = targetSource else {
            FileLogger.shared.log("Cannot select desired source: \(issueDescription ?? "not installed")")
            onIssue?(issueDescription ?? "找不到目標輸入來源。")
            if !isExplicitUserRequest {
                scheduleStartupReconciliation(after: 1_000)
            }
            onStateChange?()
            return
        }

        guard target.isEnabled && target.isSelectable else {
            FileLogger.shared.log("Cannot select disabled input source: \(target.summary)")
            onIssue?(issueDescription ?? "目標輸入來源未啟用。")
            onStateChange?()
            return
        }

        let currentIdentifier = inputSources.currentSource().identifier
        if currentIdentifier == target.identifier {
            machine.selectionSucceeded()
            pendingExplicitSelection = nil
            stopSecureRecoveryTimer()
            onStateChange?()
            return
        }

        if isSecureInputEnabled {
            if isExplicitUserRequest {
                pendingExplicitSelection = machine.desired
            }
            if !secureInputIsBlockingRecorded {
                DiagnosticMetrics.shared.recordSecureInputWait()
                FileLogger.shared.log("Secure Input is active; leaving the current source alone until it ends")
                secureInputIsBlockingRecorded = true
            }
            ensureSecureRecoveryTimer()
            onStateChange?()
            return
        }

        let attempt: Int
        if isExplicitUserRequest && !isEnabled {
            attempt = 1
        } else if let nextAttempt = machine.beginSelectionAttempt() {
            attempt = nextAttempt
        } else {
            if !didReportRetryExhaustion {
                FileLogger.shared.log("Input source selection retry limit reached; waiting for a new event or wake")
                didReportRetryExhaustion = true
            }
            onStateChange?()
            return
        }

        if !isExplicitUserRequest,
           attempt == 1,
           !allowAutomaticCorrectionTransaction() {
            onStateChange?()
            return
        }

        secureInputIsBlockingRecorded = false
        // Publish the transition before TIS runs so the host closes its shortcut
        // gate until a source notification or bounded verification resolves it.
        pendingInternalSourceID = target.identifier
        pendingSelectionWasAutomatic = !isExplicitUserRequest
        onStateChange?()
        guard !isEnvironmentSuspended, selectionAllowed() else {
            pendingInternalSourceID = nil
            pendingSelectionWasAutomatic = false
            onStateChange?()
            return
        }
        let status = inputSources.select(target)

        if status == noErr {
            FileLogger.shared.log(
                "TISSelectInputSource requested for \(target.identifier) (attempt \(attempt)/\(Configuration.maximumSelectionAttempts))"
            )
            scheduleVerification(for: target.identifier)
        } else {
            DiagnosticMetrics.shared.recordFailedSelection()
            pendingInternalSourceID = nil
            pendingSelectionWasAutomatic = false
            FileLogger.shared.log(
                "TISSelectInputSource failed for \(target.identifier), OSStatus \(status), attempt \(attempt)/\(Configuration.maximumSelectionAttempts)"
            )

            _ = inputSources.rediscover()

            if isSecureInputEnabled {
                if isExplicitUserRequest {
                    pendingExplicitSelection = machine.desired
                }
                deferAttemptsUntilSecureInputEnds()
                if !secureInputIsBlockingRecorded {
                    DiagnosticMetrics.shared.recordSecureInputWait()
                }
                secureInputIsBlockingRecorded = true
                ensureSecureRecoveryTimer()
            } else {
                scheduleNextRetryIfAllowed()
            }
        }

        onStateChange?()
    }

    private func scheduleVerification(for identifier: String) {
        cancelVerificationWork()
        let epoch = workEpoch
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted, self.workEpoch == epoch,
                  self.pendingInternalSourceID == identifier else { return }
            // Resolve, never abandon, the pending selection: it gates the host's
            // shortcuts (selectionInProgress), and TIS may post nothing at all.
            guard !self.isEnvironmentSuspended, self.selectionAllowed(), !self.isSecureInputEnabled else {
                self.pendingInternalSourceID = nil
                self.pendingSelectionWasAutomatic = false
                if self.isSecureInputEnabled {
                    self.deferAttemptsUntilSecureInputEnds()
                    self.ensureSecureRecoveryTimer()
                }
                self.onStateChange?()
                return
            }

            let currentIdentifier = self.inputSources.currentSource().identifier
            if currentIdentifier == identifier {
                let wasAutomatic = self.pendingSelectionWasAutomatic
                let restoredVChewing = identifier == self.inputSources.traditionalIdentifier
                DiagnosticMetrics.shared.recordSelectionSuccess(
                    automatic: wasAutomatic,
                    restoredVChewing: restoredVChewing
                )
                self.pendingInternalSourceID = nil
                self.pendingSelectionWasAutomatic = false
                self.machine.selectionSucceeded()
                self.lastObservedIdentifier = currentIdentifier
                self.pendingExplicitSelection = nil
                self.didReportRetryExhaustion = false
                FileLogger.shared.log("Input source selection verified: \(identifier)")
                self.onStateChange?()
            } else {
                DiagnosticMetrics.shared.recordFailedSelection()
                if let currentIdentifier, currentIdentifier != self.lastObservedIdentifier {
                    self.preserveExternalSelection(currentIdentifier, record: self.isEnabled)
                    self.onStateChange?()
                    return
                }
                self.pendingInternalSourceID = nil
                self.pendingSelectionWasAutomatic = false
                FileLogger.shared.log("Input source did not change after TIS selection: \(identifier)")

                if self.isSecureInputEnabled {
                    self.deferAttemptsUntilSecureInputEnds()
                    if !self.secureInputIsBlockingRecorded {
                        DiagnosticMetrics.shared.recordSecureInputWait()
                    }
                    self.secureInputIsBlockingRecorded = true
                    self.ensureSecureRecoveryTimer()
                } else {
                    self.scheduleNextRetryIfAllowed()
                }
                self.onStateChange?()
            }
        }

        verificationWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Configuration.verificationDelayMilliseconds),
            execute: work
        )
    }

    private func scheduleNextRetryIfAllowed() {
        guard automaticReconciliationAllowed else { return }
        guard let delay = machine.delayBeforeNextAttempt() else {
            if !didReportRetryExhaustion {
                FileLogger.shared.log("Input source selection retry limit reached; waiting for a new event or wake")
                didReportRetryExhaustion = true
            }
            return
        }

        FileLogger.shared.log("Scheduling input source retry after \(delay)ms")
        scheduleReconciliation(after: delay)
    }

    private func deferAttemptsUntilSecureInputEnds() {
        machine.selectionSucceeded()
        pendingInternalSourceID = nil
        pendingSelectionWasAutomatic = false
    }

    private func ensureSecureRecoveryTimer() {
        guard secureRecoveryTimer == nil,
              (automaticReconciliationAllowed || pendingExplicitSelection != nil),
              !isEnvironmentSuspended else {
            return
        }

        isWaitingForSecureInputToEnd = true

        let index = min(
            secureRecoveryPollIndex,
            Configuration.secureInputPollDelaysSeconds.count - 1
        )
        let delay = Configuration.secureInputPollDelaysSeconds[index]
        let epoch = workEpoch
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .seconds(delay),
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.workEpoch == epoch, self.isStarted else { return }

            self.secureRecoveryTimer?.cancel()
            self.secureRecoveryTimer = nil
            self.secureRecoveryPollIndex += 1
            self.checkForSecureInputEnd()

            if self.isWaitingForSecureInputToEnd {
                self.ensureSecureRecoveryTimer()
            }
        }

        secureRecoveryTimer = timer
        timer.resume()
    }

    private func checkForSecureInputEnd() {
        guard automaticReconciliationAllowed || pendingExplicitSelection != nil else {
            stopSecureRecoveryTimer()
            return
        }

        guard !isEnvironmentSuspended else {
            stopSecureRecoveryTimer()
            return
        }

        guard !isSecureInputEnabled else { return }

        let explicitSelection = pendingExplicitSelection
        pendingExplicitSelection = nil
        stopSecureRecoveryTimer()
        secureInputIsBlockingRecorded = false

        FileLogger.shared.log("Secure Input ended; re-discovering sources and restoring the desired input source")
        _ = inputSources.rediscover()

        if let explicitSelection {
            machine.request(explicitSelection)
            selectDesiredSource(isExplicitUserRequest: true)
            return
        }

        let currentIdentifier = inputSources.currentSource().identifier
        let observed = InputSourceManager.observedSource(
            identifier: currentIdentifier,
            discovery: inputSources.discovery
        )
        handle(machine.observe(observed, isInternalSwitch: false))
        onStateChange?()
    }

    private func stopSecureRecoveryTimer() {
        secureRecoveryTimer?.cancel()
        secureRecoveryTimer = nil
        secureRecoveryPollIndex = 0
        isWaitingForSecureInputToEnd = false
        secureInputIsBlockingRecorded = false
    }

    private func allowAutomaticCorrectionTransaction(now: Date = Date()) -> Bool {
        if let until = correctionCooldownUntil {
            if until > now {
                scheduleCorrectionCooldownRecovery(until: until)
                return false
            }
            correctionCooldownUntil = nil
            cancelCorrectionCooldownWork()
        }

        automaticCorrectionTimestamps.removeAll {
            now.timeIntervalSince($0) > Configuration.automaticCorrectionWindow
        }

        guard automaticCorrectionTimestamps.count < Configuration.automaticCorrectionLimit else {
            let until = now.addingTimeInterval(Configuration.automaticCorrectionCooldown)
            correctionCooldownUntil = until
            FileLogger.shared.log(
                "Automatic correction circuit breaker opened after \(Configuration.automaticCorrectionLimit) corrections in \(Int(Configuration.automaticCorrectionWindow)) seconds"
            )
            scheduleCorrectionCooldownRecovery(until: until)
            return false
        }

        automaticCorrectionTimestamps.append(now)
        return true
    }

    private func scheduleCorrectionCooldownRecovery(until: Date) {
        guard correctionCooldownWork == nil else { return }

        let delay = max(0, until.timeIntervalSinceNow)
        let epoch = workEpoch
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.workEpoch == epoch, self.isStarted else { return }

            self.correctionCooldownWork = nil
            guard !self.isEnvironmentSuspended else { return }

            if let currentUntil = self.correctionCooldownUntil,
               currentUntil > Date() {
                self.scheduleCorrectionCooldownRecovery(until: currentUntil)
                return
            }

            self.correctionCooldownUntil = nil
            self.automaticCorrectionTimestamps.removeAll {
                Date().timeIntervalSince($0) > Configuration.automaticCorrectionWindow
            }
            FileLogger.shared.log("Automatic correction circuit breaker closed")

            if self.isEnabled {
                self.refreshAndReconcile(reason: "Correction cooldown ended; re-checking input source")
            } else {
                self.onStateChange?()
            }
        }

        correctionCooldownWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resetCorrectionCircuitBreaker() {
        cancelCorrectionCooldownWork()
        automaticCorrectionTimestamps.removeAll()
        correctionCooldownUntil = nil
    }

    private func cancelCorrectionCooldownWork() {
        correctionCooldownWork?.cancel()
        correctionCooldownWork = nil
    }

    private func suspendForEnvironment(
        _ reason: EnvironmentSuspensionReason,
        reason logMessage: String
    ) {
        let wasSuspended = isEnvironmentSuspended
        environmentSuspensionReasons.insert(reason)
        guard !wasSuspended else { return }

        // Routine protected-App/Secure Input transitions are logged only when
        // the guard is in use; the log is not a per-App-switch activity trace.
        if isEnabled { FileLogger.shared.log("Background work paused: \(logMessage)") }
        cancelScheduledWork()
        cancelCorrectionCooldownWork()
        stopSecureRecoveryTimer()
        pendingExplicitSelection = nil
        pendingInternalSourceID = nil
        pendingSelectionWasAutomatic = false
        machine.selectionSucceeded()
        onStateChange?()
    }

    private func resumeFromEnvironment(
        _ reason: EnvironmentSuspensionReason,
        reason logMessage: String
    ) {
        let wasSuspended = isEnvironmentSuspended
        let needsReconciliation = wasSuspended || shouldReconcileAfterWake
        environmentSuspensionReasons.remove(reason)

        guard needsReconciliation, !isEnvironmentSuspended else { return }

        shouldReconcileAfterWake = false
        startupRetryCount = 0
        if isEnabled { FileLogger.shared.log("Background work resumed: \(logMessage)") }
        refreshAndReconcile(reason: logMessage)
    }

    private func cancelReconciliationWork() {
        reconciliationWork?.cancel()
        reconciliationWork = nil
    }

    private func cancelVerificationWork() {
        verificationWork?.cancel()
        verificationWork = nil
    }

    private func cancelScheduledWork() {
        if notifications.invalidate() & 2 != 0 { discoveryStale = true }
        workEpoch &+= 1
        startupWork?.cancel()
        startupWork = nil
        cancelReconciliationWork()
        cancelVerificationWork()
    }
}
