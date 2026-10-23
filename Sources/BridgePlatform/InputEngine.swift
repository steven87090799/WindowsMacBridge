import AppKit
import ApplicationServices
import Carbon
import BridgeCore

public struct EngineConfiguration: Equatable, Sendable {
    public var context = ApplicationContext()
    public var recipients: [Int32: ApplicationContext] = [:]
    public var enabled = false
    public var sessionActive = true
    public var nativeMappingAwaitingNeutral = false
    /// Policy is blocked only by Secure Input; keep the tap to observe its end.
    public var observesSecureInputEnd = false
    public var needsEventTap: Bool { sessionActive && (enabled || nativeMappingAwaitingNeutral || observesSecureInputEnd) }
    public var layoutSupported = false
    public var diagnostics = false
    public var restartToken: UInt64 = 0
    public var keyboardScope: KeyboardScope = .allKeyboards
    public var finderEnabled = false
    public var finderPermanentDeleteEnabled = false
    public var textNavigationEnabled = true
    public var altF4Enabled = false
    public var windowsKeyModifier: WindowsKeyModifier = .option
    public var macBookFnControlSwap = false
    public var winRunEnabled = false
    public var winSettingsEnabled = false
    public var winTaskViewEnabled = false
    public var finderBrightnessEnterEnabled = false
    public var screenshotEnabled = false
    public var printScreenBehavior: PrintScreenBehavior = .snipping
    public var generation: UInt64 = 0
    public var runtimePolicy: RuntimePolicySnapshot?
    public var physicalBackend: InputBackend = .eventTap
    public var inputRouting = InputRoutingSnapshot()
    public var deviceInputs: [DeviceInputPreference] = []
    public var destinationSemantics: Bool {
        physicalBackend == .deviceHID && keyboardScope == .allKeyboards &&
            !deviceInputs.contains { $0.experience == .nativeMac }
    }
    public var usesNativePhysicalMapping: Bool {
        physicalBackend == .eventTap || HIDCapturePolicy.requiresNativePassThrough(
            mode: context.mode, layoutSupported: layoutSupported, transportOnly: destinationSemantics)
    }
    public func preservesModifiers(from previous: Self) -> Bool {
        guard let runtimePolicy, let oldPolicy = previous.runtimePolicy,
              runtimePolicy.generation == generation, oldPolicy.generation == previous.generation,
              runtimePolicy.input.foreground == context, oldPolicy.input.foreground == previous.context,
              runtimePolicy.preservesModifiers(from: oldPolicy),
              usesNativePhysicalMapping == previous.usesNativePhysicalMapping else { return false }
        var normalized = self
        normalized.context = previous.context; normalized.generation = previous.generation
        normalized.recipients = previous.recipients
        normalized.layoutSupported = previous.layoutSupported
        normalized.runtimePolicy = previous.runtimePolicy
        return normalized == previous
    }
    public init() {}
}

public struct DiagnosticRecord: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let rule: String
    public let application: String
    public let microseconds: Double
    public var detail: String? = nil
}

public struct EngineStatus: Equatable, Sendable {
    public var accessibility = false
    public var listenAccess = false
    public var postAccess = false
    public var secureInput = false
    public var tapActive = false
    public var awaitingNeutral = true
    public var fault: String?
    public var emergencyPaused = false
    public var manualPassThrough = false
    public var backendIssue: String?
    public var actionStatus = ""
    public var processed: UInt64 = 0
    public var translated: UInt64 = 0
    public var maxMicroseconds: Double = 0
    public var diagnostics: [DiagnosticRecord] = []
    public init() {}
}

/// Cross-thread mailbox. The input callback only uses try(), never waits for the UI lock.
/// The run-loop maintenance tick may wait briefly so a coalesced wake cannot lose a configuration update.
private final class EngineMailbox: @unchecked Sendable {
    let lock = NSLock()
    var configuration = EngineConfiguration()
    var revision: UInt64 = 0
    var status = EngineStatus()
    var stopping = false
    var runLoop: CFRunLoop?
    var wakeQueued = false
    /// A lifecycle/host request: re-read permissions now, not on the key-edge budget.
    var authorizationCheckRequested = true
}

/// @unchecked Sendable is confined here: mutable event state belongs exclusively to run().
/// Only mailbox methods are callable across threads. No actor hops or I/O inside callback.
public final class InputEngine: @unchecked Sendable {
    private let mailbox = EngineMailbox()
    private var configuration = EngineConfiguration()
    private var revision: UInt64 = .max
    private var processor = KeyboardEventProcessor()
    private var deliveryContext: ApplicationContext?
    private var appSwitch = NativeAppSwitchLatch()
    private var remote = RemoteSourceRouter()
    public let producerInbox = InputProducerInbox()
    public let recipientInbox = InputProducerInbox()
    public let calibrationInbox = RemoteCalibrationInbox()
    private var recovery = RecoveryPolicy()
    private var status = EngineStatus()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastTrust = false
    private var lastPostAccess = false
    private var lastListenAccess = false
    private var lastSecure = false
    private var lastSessionActive = true
    private var lastRestart: UInt64 = 0
    private var attemptedStart = false
    private var needsRecreation = false
    private let marker: Int64
    private let actions: ShortcutActionDispatcher
    private var diagnostics = InputDiagnostics()
    private var publishedDiagnosticRevision: UInt64 = .max
    private var actionEpoch: UInt64 = 0
    private var tapAuthorizationFault = false
    private var policyGeneration: UInt64 = 0
    private var expiryTimer: Timer?
    private var expiryDeadline: Double?
    /// Key edges wake tick() after the callback. Permission reads (AX, Input
    /// Monitoring, posting) on that path run at most once per interval; every
    /// configuration change, host maintenance and tap-disable event forces one.
    /// Secure Input is still checked on every event in the callback itself.
    static let keyEdgeAuthorizationInterval = 1.0
    private var lastAuthorizationCheck = -Double.infinity
    private var keyEdgeWake = false
    private var activityHandler: (@MainActor @Sendable () -> Void)?
    private let activityMailbox = DeferredSignalMailbox()
    /// Fixed ring of recently reported synthetic producers. An append-only list
    /// filled after 32 short-lived posters and then hid new remote hosts until
    /// a restart or session change.
    private var observedProducers = [Int32](repeating: 0, count: 32)
    private var observedProducerNext = 0
    @MainActor public func setActivityHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        activityHandler = handler
    }
    private func notifyActivity() {
        guard activityMailbox.offer(1) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activityMailbox.take() != 0 else { return }
            MainActor.assumeIsolated { self.activityHandler?() }
        }
    }
    // Physical fallback + 16 remote ledgers, plus one app-switch modifier per remote.
    private var releases = [(UInt16, Modifiers, Int32)?](repeating: nil, count: 17 * 128 + 17)
    private var releaseCount = 0

    public init() {
        let marker = EventRewriter.generatedEventMarker
        self.marker = marker; actions = ShortcutActionDispatcher(marker: marker)
        // Compile every table before an event callback can run.
        _ = RuleEngine.browser; _ = RuleEngine.finder; _ = RuleEngine.finderExtras
        _ = RuleEngine.textNavigation; _ = RuleEngine.system
    }
    @MainActor public func setScreenshotHandler(_ handler: @escaping @MainActor @Sendable (ScreenshotKind, SourceWorkToken?) -> Void) {
        actions.onScreenshot = handler
    }
    /// Invoke once per instance, by the owning lifecycle coordinator.
    public func start() { Thread { [self] in run() }.start() }
    public func update(_ configuration: EngineConfiguration) {
        mailbox.lock.lock()
        let previous = mailbox.configuration
        let cancel = previous.context != configuration.context || previous.enabled != configuration.enabled ||
            previous.generation != configuration.generation ||
            previous.sessionActive != configuration.sessionActive || previous.keyboardScope != configuration.keyboardScope ||
            previous.finderEnabled != configuration.finderEnabled || previous.layoutSupported != configuration.layoutSupported ||
            previous.finderPermanentDeleteEnabled != configuration.finderPermanentDeleteEnabled ||
            previous.textNavigationEnabled != configuration.textNavigationEnabled ||
            previous.altF4Enabled != configuration.altF4Enabled ||
            previous.windowsKeyModifier != configuration.windowsKeyModifier ||
            previous.winRunEnabled != configuration.winRunEnabled ||
            previous.winSettingsEnabled != configuration.winSettingsEnabled ||
            previous.winTaskViewEnabled != configuration.winTaskViewEnabled ||
            previous.restartToken != configuration.restartToken || previous.physicalBackend != configuration.physicalBackend
        mailbox.configuration = configuration; mailbox.revision &+= 1
        mailbox.authorizationCheckRequested = true
        mailbox.lock.unlock()
        if cancel { actions.cancelPending() }
        else if previous.deviceInputs != configuration.deviceInputs { actions.cancelLocalPending() }
        wake()
    }
    public func snapshot() -> EngineStatus {
        mailbox.lock.lock(); defer { mailbox.lock.unlock() }
        return mailbox.status
    }
    /// Reuse the host's existing lifecycle observation when physical input is owned by HID.
    public func maintain() {
        mailbox.lock.lock(); mailbox.authorizationCheckRequested = true; mailbox.lock.unlock()
        wake()
    }
    static func authorizationCheckDue(requested: Bool, keyEdgeOnly: Bool, now: Double, last: Double) -> Bool {
        requested || !keyEdgeOnly || now - last >= keyEdgeAuthorizationInterval
    }
    public func stop() {
        actions.cancelPending(disable: true)
        mailbox.lock.lock()
        mailbox.stopping = true
        mailbox.lock.unlock()
        wake()
    }

    private func wake() {
        mailbox.lock.lock()
        guard let loop = mailbox.runLoop, !mailbox.wakeQueued else { mailbox.lock.unlock(); return }
        mailbox.wakeQueued = true; mailbox.lock.unlock()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            mailbox.lock.lock(); mailbox.wakeQueued = false; mailbox.lock.unlock()
            autoreleasepool { tick() }
        }
        CFRunLoopWakeUp(loop)
    }

    private func run() {
        Thread.current.name = "WindowsMacBridge.Input"
        mailbox.lock.lock(); mailbox.runLoop = CFRunLoopGetCurrent(); mailbox.lock.unlock()
        // A source keeps the inactive loop alive without a recurring timer.
        var context = CFRunLoopSourceContext()
        context.perform = { _ in }
        let idleSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
        CFRunLoopAddSource(CFRunLoopGetCurrent(), idleSource, .commonModes)
        autoreleasepool { tick() }
        CFRunLoopRun()
        expiryTimer?.invalidate(); expiryTimer = nil
        queueReleases(); deliverReleases()
        mailbox.lock.lock(); mailbox.runLoop = nil; mailbox.lock.unlock()
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), idleSource, .commonModes)
        destroyTap()
        actions.update(context: .init(), enabled: false)
    }

    private func readConfiguration() {
        // update() coalesces run-loop wakes. Skipping this read on lock contention
        // can leave the remote-source routing/semantics stale until another
        // unrelated wake (the observed VNC workaround was toggling Windows Mode).
        // This runs outside the keyboard callback; the mailbox copy is bounded.
        mailbox.lock.lock()
        let changed = revision != mailbox.revision
        let deviceChanged = changed && configuration.deviceInputs != mailbox.configuration.deviceInputs
        let deliveryChanged = changed && configuration.destinationSemantics != mailbox.configuration.destinationSemantics
        let preserveModifiers = changed && mailbox.configuration.preservesModifiers(from: configuration)
        if changed {
            if configuration.context != mailbox.configuration.context { deliveryContext = nil }
            configuration = mailbox.configuration; revision = mailbox.revision
        }
        mailbox.lock.unlock()
        if changed {
            if configuration.restartToken != lastRestart || configuration.sessionActive != lastSessionActive {
                for i in observedProducers.indices { observedProducers[i] = 0 }
            }
            if deliveryChanged { needsRecreation = true; attemptedStart = false }
            if deviceChanged {
                processor.drainTranslatedReleases { key, flags, pid in
                    guard releaseCount < releases.count else { return }
                    releases[releaseCount] = (key, flags, pid); releaseCount += 1
                }
                processor.invalidate()
            }
            if policyGeneration != configuration.generation {
                queueReleases(invalidateRemote: !preserveModifiers)
                policyGeneration = configuration.generation; actionEpoch &+= 1
                if !preserveModifiers { processor.invalidate() }
            }
            if lastRestart != configuration.restartToken {
                lastRestart = configuration.restartToken
                status.fault = nil; tapAuthorizationFault = false; status.emergencyPaused = false
                recovery.reset(); attemptedStart = false
                needsRecreation = true
                processor.invalidate()
                processor.resumeManualPassThrough()
                actionEpoch &+= 1
            }
            diagnostics.configure(enabled: configuration.diagnostics, now: ProcessInfo.processInfo.systemUptime)
        }
        if changed { configureProcessor(preservingModifiersOnAppChange: preserveModifiers) }
    }

    private func queueReleases(invalidateRemote: Bool = true) {
        appSwitch.drain { key, flags, pid in
            guard releaseCount < releases.count else { return }
            releases[releaseCount] = (key, flags, pid); releaseCount += 1
        }
        processor.drainTranslatedReleases { key, flags, pid in
            guard releaseCount < releases.count else { return }
            releases[releaseCount] = (key, flags, pid); releaseCount += 1
        }
        if invalidateRemote {
            remote.invalidate { key, flags, pid in
                guard releaseCount < releases.count else { return }
                releases[releaseCount] = (key, flags, pid); releaseCount += 1
            }
        }
    }
    private func deliverReleases() {
        guard releaseCount > 0 else { return }
        let allowed = configuration.sessionActive && !IsSecureEventInputEnabled() && CGPreflightPostEventAccess()
        for i in 0..<releaseCount {
            if allowed, let (key, flags, pid) = releases[i] {
                if key == 54 || key == 55 {
                    NativeSessionEmitter.prepare(type: .flagsChanged, keyCode: key, modifiers: flags, marker: marker)?.post(tap: .cgSessionEventTap)
                } else if pid > 0, let up = NativeSessionEmitter.prepare(type: .keyUp, keyCode: key, modifiers: flags, marker: marker) {
                    up.postToPid(pid)
                }
            }
            releases[i] = nil
        }
        releaseCount = 0
    }

    private func configureProcessor(preservingModifiersOnAppChange: Bool = false) {
        let scopeSupported = configuration.physicalBackend != .eventTap || BackendCapabilities.eventTap.supports(configuration.keyboardScope, preferences: configuration.deviceInputs)
        status.backendIssue = !scopeSupported ? "指定鍵盤範圍／Native Mac 偏好需要裝置 HID；備援已停止實體快捷鍵翻譯，遠端來源保持獨立。" :
            configuration.physicalBackend == .deviceHID && !configuration.destinationSemantics ?
            "混合 Native Mac／Windows 裝置無法從接收事件區分 UC 來源；Finder／AX 操作保持停用。" : nil
        let active = configuration.enabled && configuration.sessionActive &&
            status.accessibility && status.postAccess && hasInputAuthorization && !status.secureInput &&
            status.fault == nil && !status.emergencyPaused && scopeSupported
        let recipientContext = deliveryContext ?? configuration.context
        processor.configure(context: recipientContext,
                            enabled: active && (configuration.physicalBackend == .eventTap || configuration.destinationSemantics), layoutSupported: configuration.layoutSupported,
                            controlsEnabled: active && configuration.physicalBackend == .eventTap, finderEnabled: configuration.finderEnabled,
                            finderPermanentDeleteEnabled: configuration.finderPermanentDeleteEnabled,
                            textNavigationEnabled: configuration.textNavigationEnabled,
                            altF4Enabled: configuration.altF4Enabled,
                            windowsKeyModifier: configuration.windowsKeyModifier,
                            winRunEnabled: configuration.winRunEnabled,
                            winSettingsEnabled: configuration.winSettingsEnabled,
                            winTaskViewEnabled: configuration.winTaskViewEnabled,
                            nativeAppSwitchEnabled: configuration.physicalBackend == .eventTap || configuration.destinationSemantics,
                            screenshotEnabled: configuration.screenshotEnabled,
                            printScreen: configuration.printScreenBehavior,
                            preservingModifiersOnAppChange: preservingModifiersOnAppChange)
        var sourcePolicy = SourceTranslationConfiguration()
        sourcePolicy.context = recipientContext
        sourcePolicy.enabled = configuration.enabled && configuration.sessionActive && status.accessibility && status.postAccess && hasInputAuthorization &&
            !status.secureInput && status.fault == nil && !status.emergencyPaused && !processor.manualPassThrough
        sourcePolicy.layoutSupported = configuration.layoutSupported
        sourcePolicy.finderEnabled = configuration.finderEnabled
        sourcePolicy.finderPermanentDeleteEnabled = configuration.finderPermanentDeleteEnabled
        sourcePolicy.textNavigationEnabled = configuration.textNavigationEnabled
        sourcePolicy.altF4Enabled = configuration.altF4Enabled
        sourcePolicy.winRunEnabled = configuration.winRunEnabled; sourcePolicy.winSettingsEnabled = configuration.winSettingsEnabled
        sourcePolicy.winTaskViewEnabled = configuration.winTaskViewEnabled
        sourcePolicy.screenshotEnabled = configuration.screenshotEnabled
        sourcePolicy.printScreen = configuration.printScreenBehavior; sourcePolicy.generation = configuration.generation
        remote.update(configuration.inputRouting, configuration: sourcePolicy,
                      preservingModifiersOnAppChange: preservingModifiersOnAppChange) { key, flags, pid in
            guard releaseCount < releases.count else { return }
            releases[releaseCount] = (key, flags, pid); releaseCount += 1
        }
        _ = actions.update(context: configuration.context,
                           enabled: sourcePolicy.enabled && !processor.manualPassThrough,
                           finderEnabled: configuration.finderEnabled,
                           finderPermanentDeleteEnabled: configuration.finderPermanentDeleteEnabled,
                           epoch: actionEpoch)
    }

    private func tick() {
        readConfiguration()
        mailbox.lock.lock()
        let stopping = mailbox.stopping, requested = mailbox.authorizationCheckRequested
        mailbox.authorizationCheckRequested = false
        mailbox.lock.unlock()
        if stopping { queueReleases(); deliverReleases(); CFRunLoopStop(CFRunLoopGetCurrent()); return }
        if needsRecreation { destroyTap(); needsRecreation = false }

        let now = ProcessInfo.processInfo.systemUptime
        let keyEdgeOnly = keyEdgeWake; keyEdgeWake = false
        if Self.authorizationCheckDue(requested: requested || tap == nil, keyEdgeOnly: keyEdgeOnly, now: now, last: lastAuthorizationCheck) {
            lastAuthorizationCheck = now
            status.accessibility = AXIsProcessTrusted()
            status.listenAccess = CGPreflightListenEventAccess()
            status.postAccess = CGPreflightPostEventAccess()
            status.secureInput = IsSecureEventInputEnabled()
        }
        remote.expire(at: ProcessInfo.processInfo.systemUptime) { key, flags, pid in
            guard releaseCount < releases.count else { return }
            releases[releaseCount] = (key, flags, pid); releaseCount += 1
        }
        if status.accessibility != lastTrust || status.postAccess != lastPostAccess || status.listenAccess != lastListenAccess || status.secureInput != lastSecure ||
            configuration.sessionActive != lastSessionActive {
            queueReleases()
            processor.invalidate()
            actionEpoch &+= 1
            if (status.accessibility && !lastTrust) || (status.postAccess && !lastPostAccess) ||
                (status.listenAccess && !lastListenAccess) {
                attemptedStart = false
                if tapAuthorizationFault && status.accessibility && status.postAccess && status.listenAccess {
                    status.fault = nil; tapAuthorizationFault = false
                }
            }
            lastTrust = status.accessibility; lastSecure = status.secureInput
            lastPostAccess = status.postAccess
            lastListenAccess = status.listenAccess
            lastSessionActive = configuration.sessionActive
        }
        deliverReleases()
        if !configuration.needsEventTap || !status.accessibility || !status.postAccess || !hasInputAuthorization {
            destroyTap()
            attemptedStart = false
        } else if tap == nil && configuration.needsEventTap && !attemptedStart && status.fault == nil {
            attemptedStart = true
            createTap()
        }
        configureProcessor()
        if (configuration.physicalBackend == .eventTap || configuration.destinationSemantics) && tap != nil && configuration.enabled && configuration.sessionActive && status.accessibility &&
            !status.secureInput && processor.isAwaitingNeutral && hardwareIsNeutral() {
            processor.reconcileNeutralHardware()
        }
        status.tapActive = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        status.awaitingNeutral = processor.isAwaitingNeutral
        status.processed = processor.processedCount &+ remote.processedCount
        status.translated = processor.translatedCount &+ remote.translatedCount
        status.manualPassThrough = processor.manualPassThrough
        status.actionStatus = actions.status()
        diagnostics.expire(at: now)
        // Build diagnostics only when the ring changes; idle ticks allocate nothing here.
        if publishedDiagnosticRevision != diagnostics.revision {
            status.diagnostics = diagnostics.snapshot()
            publishedDiagnosticRevision = diagnostics.revision
        }
        mailbox.lock.lock(); let previous = mailbox.status; mailbox.status = status; mailbox.lock.unlock()
        if Self.requiresHostWake(previous: previous, next: status,
                                 everyChange: diagnostics.isActive(at: now) || configuration.nativeMappingAwaitingNeutral) {
            notifyActivity()
        }
        scheduleExpiry()
    }
    /// Counters advance on every key edge. Waking the host for them ran a full
    /// MainActor tick (TCC reads, policy, registry, SwiftUI publish) per keystroke.
    /// They are still published with the next material change or on request.
    /// Live diagnostics and a pending Fn/Ctrl neutral check still need key edges.
    static func requiresHostWake(previous: EngineStatus, next: EngineStatus, everyChange: Bool) -> Bool {
        if everyChange { return previous != next }
        var before = previous, after = next
        before.processed = 0; before.translated = 0; before.maxMicroseconds = 0
        after.processed = 0; after.translated = 0; after.maxMicroseconds = 0
        return before != after
    }
    private var hasInputAuthorization: Bool {
        status.listenAccess
    }
    /// One shared one-shot timer for held remote keys and diagnostic expiry.
    /// This also releases diagnostic storage while input and the host are idle.
    private func scheduleExpiry() {
        let deadline: Double?
        switch (remote.nextExpiry, diagnostics.deadline) {
        case let (a?, b?): deadline = min(a, b)
        case let (a?, nil): deadline = a
        case let (nil, b?): deadline = b
        case (nil, nil): deadline = nil
        }
        if deadline == expiryDeadline, deadline == nil || expiryTimer?.isValid == true { return }
        expiryTimer?.invalidate(); expiryTimer = nil; expiryDeadline = deadline
        guard let deadline else { return }
        let timer = Timer(timeInterval: max(0.05, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            autoreleasepool { self?.expiryDeadline = nil; self?.tick() }
        }
        expiryTimer = timer; RunLoop.current.add(timer, forMode: .common)
    }

    private func hardwareIsNeutral() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        if !Self.modifiers(flags).isEmpty { return false }
        for key in UInt16(0)..<128 where key != 57 { // Caps Lock is a latch, not a held modifier.
            if CGEventSource.keyState(.hidSystemState, key: key) { return false }
        }
        return true
    }

    private func createTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<InputEngine>.fromOpaque(userInfo).takeUnretainedValue()
            return engine.handle(type, event: event)
        }
        // Recipient evidence is available at annotated delivery. System shortcuts
        // use a narrow native-session emitter after this destination check.
        guard let created = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                              options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                              callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            tapAuthorizationFault = true
            status.fault = "鍵盤事件尚未就緒；請確認輔助功能與輸入監控。"
            return
        }
        tap = created; source = runSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        guard KeyboardEventTapCoverage.currentProcessIsVerified(tap: created) else {
            destroyTap()
            tapAuthorizationFault = true
            status.fault = "鍵盤事件尚未就緒；請確認輔助功能與輸入監控。"
            return
        }
        processor.invalidate()
    }

    private func destroyTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            mailbox.lock.lock(); mailbox.authorizationCheckRequested = true; mailbox.lock.unlock()
            queueReleases(); wake()
            processor.invalidate()
            actionEpoch &+= 1
            if configuration.enabled && configuration.sessionActive && status.accessibility &&
                !status.secureInput && !status.emergencyPaused && status.fault == nil &&
                recovery.mayRetry(at: ProcessInfo.processInfo.systemUptime), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                status.fault = "Event Tap 已停用；請放開按鍵後重新啟動。"
            }
            configureProcessor()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
        // Secure Input can change without an App notification. Keep ONE native
        // check per real input event; never cache it only on focus changes.
        let secure = IsSecureEventInputEnabled()
        if secure != status.secureInput {
            queueReleases(); processor.invalidate(); status.secureInput = secure
            configureProcessor(); wake()
        }
        if secure { return Unmanaged.passUnretained(event) }
        readConfiguration()
        // Secure/session gaps must never perform delayed cleanup by rewriting input.
        if status.secureInput || !configuration.sessionActive || !status.accessibility || !status.postAccess || !hasInputAuthorization {
            return Unmanaged.passUnretained(event)
        }
        let evidence = InputOriginEvidence(processID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
                                           stateID: event.getIntegerValueField(.eventSourceStateID),
                                           ownEvent: event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()))
        let origin = configuration.inputRouting.classify(evidence, physicalBackend: configuration.physicalBackend)
        let recipient = Int32(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        let key = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = Self.modifiers(event.flags)
        let trace = diagnostics.deadline != nil && diagnostics.isActive(at: ProcessInfo.processInfo.systemUptime) &&
            Self.tracesShortcutInput(type: type, key: key, flags: flags,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        let traceStart = trace ? DispatchTime.now().uptimeNanoseconds : 0
        let traceAwaiting = trace && processor.isAwaitingNeutral
        let traceSynchronized = trace && processor.modifiers.synchronized
        let traceRawFlags = trace ? event.flags.rawValue : 0
        var traceResult = "source-filter"
        defer {
            if trace {
                // Bounded, opt-in metadata only. No characters, clipboard reads,
                // file I/O or claims of event-to-physical-device correlation.
                let detail = "key=\(key) type=\(type.rawValue) flags=\(flags.rawValue) rawFlags=0x\(String(traceRawFlags, radix: 16)) " +
                    "source=\(evidence.processID)/\(evidence.stateID) origin=\(origin) target=\(recipient) " +
                    "enabled=\(configuration.enabled) neutralWait=\(traceAwaiting)->\(processor.isAwaitingNeutral) " +
                    "synchronized=\(traceSynchronized)->\(processor.modifiers.synchronized) result=\(traceResult)"
                appendDiagnostic(rule: "input-shortcut", application: (deliveryContext ?? configuration.context).bundleID,
                    microseconds: Double(DispatchTime.now().uptimeNanoseconds - traceStart) / 1000, detail: detail)
                wake()
            }
        }
        if type == .keyDown, key == 8, recipient > 0,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           flags == .control || flags == .command {
            actions.observeNativeCopy()
        }
        let localDelivery = DestinationSemanticPolicy.acceptsDelivery(
            target: recipient,
            foreground: configuration.context.processID)
        // HID's default profile transports raw keys. This second stage runs only after
        // WindowServer identifies a recipient on this Mac. Never infer it from source focus.
        let destinationPhysical = !evidence.ownEvent &&
            (configuration.destinationSemantics && evidence.processID == 0 && evidence.stateID == 1 || origin == .universalControl)
        let physical = origin == .physicalFallback || destinationPhysical
        if evidence.processID > 0 && !evidence.ownEvent &&
            !configuration.inputRouting.producers.contains(where: { $0.processID == evidence.processID }) &&
            !observedProducers.contains(evidence.processID) {
            observedProducers[observedProducerNext] = evidence.processID
            observedProducerNext = (observedProducerNext + 1) % observedProducers.count
            producerInbox.observe(evidence.processID); notifyActivity()
        }
        guard physical || { if case .remote = origin { return true }; return false }() else {
            return Unmanaged.passUnretained(event)
        }
        traceResult = "recipient-filter"
        defer { keyEdgeWake = true; wake() } // Coalesced work after callback, no recurring poll.
        let start = DispatchTime.now().uptimeNanoseconds
        let side = Self.side(key)
        // flagsChanged describes state, not a toggle. UC's virtual HID services
        // can emit the same modifier-down more than once.
        let independentRemoteFlags: Bool
        if case .remote(let index) = origin {
            independentRemoteFlags = configuration.inputRouting.producers[index].independentFlags
        } else { independentRemoteFlags = false }
        let down = physical || independentRemoteFlags ? side.map { Self.modifierDown($0, flags: event.flags) } : nil
        let phase: KeyPhase = type == .keyDown ? .down : type == .keyUp ? .up : .flagsChanged
        // Modifier edges and owned ups still reconcile state across missing recipients.
        // A new shortcut requires a known local recipient; only an existing native switcher
        // can accept another Tab while WindowServer has temporarily no App recipient.
        let nativeTabHeld = physical ? appSwitch.isActive(for: (deliveryContext ?? configuration.context).processID) : remote.hasNativeAppSwitchSession(evidence)
        if phase == .down && !DestinationSemanticPolicy.acceptsKeyDown(target: recipient,
            foreground: configuration.context.processID, key: key, nativeTabHeld: nativeTabHeld) {
            return Unmanaged.passUnretained(event)
        }
        if recipient > 0 {
            let resolved = DestinationSemanticPolicy.context(target: recipient,
                foreground: configuration.context, recipients: configuration.recipients)
            // Unknown modifier recipients still reconcile physical state. A new
            // key-down cannot borrow the foreground App's rules.
            if phase == .down && resolved == nil { return Unmanaged.passUnretained(event) }
            if resolved?.clipboardOnly == true {
                recipientInbox.observe(recipient); notifyActivity()
            }
            if let context = resolved,
               context != (deliveryContext ?? configuration.context) {
                // Reconfiguring the router below retires its old outputs and
                // actions. Do not first invalidate its held Control history.
                queueReleases(invalidateRemote: false)
                deliveryContext = context
                configureProcessor(preservingModifiersOnAppChange: true)
            }
        }
        var normalized = KeyboardEvent(phase, keyCode: key, modifiers: flags,
                                       isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                       modifierSide: side, modifierDown: down)
        normalized.finderMovePending = actions.hasPendingFinderCut
        if calibrationInbox.observe(processID: evidence.processID, key: key, phase: phase, flags: flags, repeatKey: normalized.isRepeat) {
            notifyActivity()
        }
        traceResult = "processor"
        var routed = physical ? RoutedInputDecision(destinationPhysical ? processor.processIndependentSource(normalized) : processor.process(normalized)) :
            remote.process(normalized, evidence: evidence, now: ProcessInfo.processInfo.systemUptime)
        if physical && configuration.windowsKeyModifier == .command {
            routed.decision = appSwitch.apply(routed.decision, event: normalized, state: processor.modifiers,
                                             target: (deliveryContext ?? configuration.context).processID)
        }
        var decision = routed.decision
        if case .action(let action, _) = decision {
            if localDelivery && actions.submit(action, context: configuration.context, source: routed.validity) {
                decision = .suppress
            } else if routed.validity?.isCurrent != false,
                      let fallback = physical ? processor.fallbackForRejectedClipboardAction(keyCode: key) :
                        remote.fallbackForRejectedClipboardAction(keyCode: key, evidence: evidence) {
                actions.observeNativeCopy()
                decision = fallback
            } else {
                if physical { processor.rejectAction(keyCode: key) }
                else { remote.rejectAction(keyCode: key, evidence: evidence) }
                decision = .passThrough
            }
        }
        var result: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
        switch decision {
        case .passThrough: traceResult = "pass"
        case .suppress: traceResult = "suppress"; result = nil
        case .emergencyPause:
            traceResult = "emergency-pause"
            queueReleases(); wake()
            status.emergencyPaused = true
            configureProcessor()
            result = nil
        case .togglePassThrough:
            traceResult = "manual-pass-through"
            queueReleases(); wake()
            status.manualPassThrough = processor.manualPassThrough
            configureProcessor()
            result = nil
        case .action: traceResult = "action" // Resolved above, including the paired clipboard fallback.
        case let .rewrite(outputKey, outputModifiers, ruleID):
            if trace { traceResult = "rewrite:\(ruleID)" }
            if NativeSessionEmitter.requiresSessionRouting(ruleID) {
                // Synchronous input delivery: no detached work, queue or timer. Policy
                // and source validity are checked at the point of native dispatch.
                if configuration.enabled && !status.emergencyPaused && status.fault == nil &&
                    !processor.manualPassThrough && routed.validity?.isCurrent != false &&
                    !status.secureInput,
                   let output = NativeSessionEmitter.prepare(type: type, keyCode: outputKey, modifiers: outputModifiers, marker: marker) {
                    output.post(tap: .cgSessionEventTap); result = nil
                }
            } else {
                if let output = EventRewriter.clipboardReplacement(for: event, keyCode: outputKey, modifiers: outputModifiers, marker: marker) {
                    // Quartz owns and releases a replacement returned by the
                    // tap. Transfer one retain; ARC keeps no per-key history.
                    result = Unmanaged.passRetained(output)
                } else {
                    EventRewriter.apply(to: event, keyCode: outputKey, modifiers: outputModifiers, marker: marker)
                }
            }
            if phase == .down && !normalized.isRepeat && diagnostics.deadline != nil &&
                diagnostics.isActive(at: ProcessInfo.processInfo.systemUptime) {
                appendDiagnostic(rule: ruleID, application: (deliveryContext ?? configuration.context).bundleID,
                    microseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1000
        status.maxMicroseconds = max(status.maxMicroseconds, elapsed)
        return result
    }

    /// Restrict short-term traces to modifier edges and clipboard chords, never ordinary text.
    static func tracesShortcutInput(type: CGEventType, key: UInt16, flags: Modifiers, isRepeat: Bool) -> Bool {
        if type == .flagsChanged { return key == 59 || key == 62 || key == 63 }
        guard type == .keyDown, !isRepeat,
              !flags.intersection([.control, .command, .fn]).isEmpty else { return false }
        return key == 0 || key == 7 || key == 8 || key == 9
    }
    static func modifierDown(_ side: ModifierSide, flags: CGEventFlags) -> Bool {
        guard modifiers(flags).contains(side.group) else { return false }
        // Native side masks from IOKit's IOLLEvent.h. They distinguish a side's
        // release while its peer remains held, without toggling duplicate downs.
        let masks: (own: UInt64, group: UInt64)
        switch side {
        case .leftControl: masks = (0x1, 0x2001)
        case .rightControl: masks = (0x2000, 0x2001)
        case .leftShift: masks = (0x2, 0x6)
        case .rightShift: masks = (0x4, 0x6)
        case .leftCommand: masks = (0x8, 0x18)
        case .rightCommand: masks = (0x10, 0x18)
        case .leftOption: masks = (0x20, 0x60)
        case .rightOption: masks = (0x40, 0x60)
        }
        if flags.rawValue & masks.group != 0 { return flags.rawValue & masks.own != 0 }
        // Aggregate-only transports cannot identify a release while the peer
        // stays down. Preserve the reported held group until its neutral edge;
        // never invent a release from an identical repeated event.
        return true
    }
    private func appendDiagnostic(rule: String, application: String, microseconds: Double, detail: String? = nil) {
        diagnostics.append(rule: rule, application: application, microseconds: microseconds,
            detail: detail, now: ProcessInfo.processInfo.systemUptime)
    }

    public static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var value: Modifiers = []
        if flags.contains(.maskControl) { value.insert(.control) }
        if flags.contains(.maskCommand) { value.insert(.command) }
        if flags.contains(.maskAlternate) { value.insert(.option) }
        if flags.contains(.maskShift) { value.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { value.insert(.fn) }
        return value
    }
    public static func replacingModifiers(_ original: CGEventFlags, with value: Modifiers) -> CGEventFlags {
        var flags = original.subtracting([.maskControl, .maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn])
        // Remove device-dependent side bits as well; otherwise raw Ctrl flags leak into Cmd events.
        let sideMask: UInt64 = 0x00000001 | 0x00000002 | 0x00000004 | 0x00000008 |
                              0x00000010 | 0x00000020 | 0x00000040 | 0x00002000
        flags = CGEventFlags(rawValue: flags.rawValue & ~sideMask)
        if value.contains(.control) { flags.insert(.maskControl) }
        if value.contains(.command) { flags.insert(.maskCommand) }
        if value.contains(.option) { flags.insert(.maskAlternate) }
        if value.contains(.shift) { flags.insert(.maskShift) }
        if value.contains(.fn) { flags.insert(.maskSecondaryFn) }
        return flags
    }
    private static func side(_ key: UInt16) -> ModifierSide? {
        switch key {
        case 59: .leftControl
        case 62: .rightControl
        case 55: .leftCommand
        case 54: .rightCommand
        case 58: .leftOption
        case 61: .rightOption
        case 56: .leftShift
        case 60: .rightShift
        default: nil
        }
    }
}
