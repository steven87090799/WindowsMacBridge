import AppKit
import ApplicationServices
import Carbon
import BridgeCore

public struct EngineConfiguration: Sendable {
    public var context = ApplicationContext()
    public var enabled = false
    public var sessionActive = true
    public var layoutSupported = false
    public var diagnostics = false
    public var restartToken: UInt64 = 0
    public var keyboardScope: KeyboardScope = .builtInAndApple834
    public var finderEnabled = false
    public var finderPermanentDeleteEnabled = false
    public var textNavigationEnabled = true
    public var altF4Enabled = false
    public var altF4QuitLastWindow = false
    public var windowsKeyModifier: WindowsKeyModifier = .option
    public var macBookFnControlSwap = false
    public var winRunEnabled = false
    public var winSettingsEnabled = false
    public var winTaskViewEnabled = false
    public init() {}
}

public struct DiagnosticRecord: Equatable, Sendable, Identifiable {
    public let id: UInt64
    public let rule: String
    public let application: String
    public let microseconds: Double
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

/// Cross-thread mailbox. Input callback only uses try(), never waits for the UI lock.
private final class EngineMailbox: @unchecked Sendable {
    let lock = NSLock()
    var configuration = EngineConfiguration()
    var revision: UInt64 = 0
    var status = EngineStatus()
    var stopping = false
}

/// @unchecked Sendable is confined here: mutable event state belongs exclusively to run().
/// Only mailbox methods are callable across threads. No actor hops or I/O inside callback.
public final class InputEngine: @unchecked Sendable {
    private let mailbox = EngineMailbox()
    private var configuration = EngineConfiguration()
    private var revision: UInt64 = .max
    private var processor = KeyboardEventProcessor()
    private var recovery = RecoveryPolicy()
    private var status = EngineStatus()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastTrust = false
    private var lastSecure = false
    private var lastSessionActive = true
    private var lastRestart: UInt64 = 0
    private var attemptedStart = false
    private var needsRecreation = false
    private let marker: Int64
    private let actions: ShortcutActionDispatcher
    private var records = [DiagnosticRecord?](repeating: nil, count: 128)
    private var recordIndex = 0
    private var recordSequence: UInt64 = 0
    private var diagnosticRevision: UInt64 = 0
    private var publishedDiagnosticRevision: UInt64 = .max
    private var diagnosticDeadline: TimeInterval = 0
    private var actionEpoch: UInt64 = 0

    public init() {
        let marker = EventRewriter.generatedEventMarker
        self.marker = marker; actions = ShortcutActionDispatcher(marker: marker)
        // Compile every table before an event callback can run.
        _ = RuleEngine.browser; _ = RuleEngine.finder; _ = RuleEngine.finderExtras
        _ = RuleEngine.textNavigation; _ = RuleEngine.system
    }
    /// Invoke once per instance, by the owning lifecycle coordinator.
    public func start() { Thread { [self] in run() }.start() }
    public func update(_ configuration: EngineConfiguration) {
        mailbox.lock.lock()
        let previous = mailbox.configuration
        let cancel = previous.context != configuration.context || previous.enabled != configuration.enabled ||
            previous.sessionActive != configuration.sessionActive || previous.keyboardScope != configuration.keyboardScope ||
            previous.finderEnabled != configuration.finderEnabled || previous.layoutSupported != configuration.layoutSupported ||
            previous.finderPermanentDeleteEnabled != configuration.finderPermanentDeleteEnabled ||
            previous.textNavigationEnabled != configuration.textNavigationEnabled ||
            previous.altF4Enabled != configuration.altF4Enabled ||
            previous.altF4QuitLastWindow != configuration.altF4QuitLastWindow ||
            previous.windowsKeyModifier != configuration.windowsKeyModifier ||
            previous.winRunEnabled != configuration.winRunEnabled ||
            previous.winSettingsEnabled != configuration.winSettingsEnabled ||
            previous.winTaskViewEnabled != configuration.winTaskViewEnabled ||
            previous.restartToken != configuration.restartToken
        mailbox.configuration = configuration; mailbox.revision &+= 1
        mailbox.lock.unlock()
        if cancel { actions.cancelPending() }
    }
    public func snapshot() -> EngineStatus {
        mailbox.lock.lock(); defer { mailbox.lock.unlock() }
        return mailbox.status
    }
    public func stop() {
        actions.cancelPending(disable: true)
        mailbox.lock.lock(); defer { mailbox.lock.unlock() }
        mailbox.stopping = true
    }

    private func run() {
        Thread.current.name = "WindowsMacBridge.Input"
        let timer = Timer(timeInterval: 0.25, repeats: true) { [self] _ in autoreleasepool { tick() } }
        timer.tolerance = 0.025
        RunLoop.current.add(timer, forMode: .common)
        autoreleasepool { tick() }
        CFRunLoopRun()
        timer.invalidate()
        destroyTap()
        actions.update(context: .init(), enabled: false)
    }

    private func readConfiguration() {
        guard mailbox.lock.try() else { return }
        let changed = revision != mailbox.revision
        if changed { configuration = mailbox.configuration; revision = mailbox.revision }
        mailbox.lock.unlock()
        if changed {
            if lastRestart != configuration.restartToken {
                lastRestart = configuration.restartToken
                status.fault = nil; status.emergencyPaused = false
                recovery.reset(); attemptedStart = false
                needsRecreation = true
                processor.invalidate()
                processor.resumeManualPassThrough()
                actionEpoch &+= 1
            }
            if !configuration.diagnostics {
                if diagnosticDeadline != 0 || !status.diagnostics.isEmpty {
                    for i in records.indices { records[i] = nil }
                    diagnosticRevision &+= 1
                }
                diagnosticDeadline = 0
            } else if diagnosticDeadline == 0 {
                diagnosticDeadline = ProcessInfo.processInfo.systemUptime + 300
            }
        }
        if changed { configureProcessor() }
    }

    private func configureProcessor() {
        let scopeSupported = BackendCapabilities.eventTap.supports(configuration.keyboardScope)
        status.backendIssue = scopeSupported ? nil : "內建鍵盤限定需要裝置攔截後端；目前不會套用到其他鍵盤。"
        let active = configuration.enabled && configuration.sessionActive &&
            status.accessibility && status.postAccess && !status.secureInput &&
            status.fault == nil && !status.emergencyPaused && scopeSupported
        processor.configure(context: configuration.context,
                            enabled: active, layoutSupported: configuration.layoutSupported,
                            controlsEnabled: active, finderEnabled: configuration.finderEnabled,
                            finderPermanentDeleteEnabled: configuration.finderPermanentDeleteEnabled,
                            textNavigationEnabled: configuration.textNavigationEnabled,
                            altF4Enabled: configuration.altF4Enabled,
                            windowsKeyModifier: configuration.windowsKeyModifier,
                            winRunEnabled: configuration.winRunEnabled,
                            winSettingsEnabled: configuration.winSettingsEnabled,
                            winTaskViewEnabled: configuration.winTaskViewEnabled)
        if !actions.update(context: configuration.context,
                           enabled: active && configuration.layoutSupported && !processor.manualPassThrough,
                           finderEnabled: configuration.finderEnabled,
                           finderPermanentDeleteEnabled: configuration.finderPermanentDeleteEnabled,
                           altF4QuitLastWindow: configuration.altF4QuitLastWindow,
                           epoch: actionEpoch) {
            processor.invalidate()
        }
    }

    private func tick() {
        readConfiguration()
        mailbox.lock.lock(); let stopping = mailbox.stopping; mailbox.lock.unlock()
        if stopping { CFRunLoopStop(CFRunLoopGetCurrent()); return }
        if needsRecreation { destroyTap(); needsRecreation = false }

        status.accessibility = AXIsProcessTrusted()
        status.listenAccess = CGPreflightListenEventAccess()
        status.postAccess = CGPreflightPostEventAccess()
        status.secureInput = IsSecureEventInputEnabled()
        if status.accessibility != lastTrust || status.secureInput != lastSecure ||
            configuration.sessionActive != lastSessionActive {
            processor.invalidate()
            actionEpoch &+= 1
            if status.accessibility && !lastTrust { attemptedStart = false }
            lastTrust = status.accessibility; lastSecure = status.secureInput
            lastSessionActive = configuration.sessionActive
        }
        if !status.accessibility || !status.postAccess || !configuration.sessionActive {
            destroyTap()
            attemptedStart = false
        } else if tap == nil && configuration.enabled && !attemptedStart && status.fault == nil {
            attemptedStart = true
            createTap()
        }
        configureProcessor()
        if tap != nil && configuration.enabled && configuration.sessionActive && status.accessibility &&
            !status.secureInput && processor.isAwaitingNeutral && hardwareIsNeutral() {
            processor.reconcileNeutralHardware()
        }
        status.tapActive = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        status.awaitingNeutral = processor.isAwaitingNeutral
        status.processed = processor.processedCount; status.translated = processor.translatedCount
        status.manualPassThrough = processor.manualPassThrough
        status.actionStatus = actions.status()
        if diagnosticDeadline > 0 && ProcessInfo.processInfo.systemUptime >= diagnosticDeadline {
            for i in records.indices { records[i] = nil }
            diagnosticDeadline = 0
            diagnosticRevision &+= 1
        }
        // Build diagnostics only when the ring changes; idle ticks allocate nothing here.
        if publishedDiagnosticRevision != diagnosticRevision {
            status.diagnostics = records.compactMap { $0 }.sorted { $0.id > $1.id }
            publishedDiagnosticRevision = diagnosticRevision
        }
        mailbox.lock.lock(); mailbox.status = status; mailbox.lock.unlock()
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
        // Screenshot claims the original Win+Shift+S at the session head. Keep
        // Ctrl translations at the tail even when either tap is recreated.
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                              options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                              callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            status.fault = "無法建立 Event Tap；請檢查權限後按重新啟動。"
            return
        }
        tap = created; source = runSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        processor.invalidate()
    }

    private func destroyTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
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
        readConfiguration()
        // Secure/session gaps must never perform delayed cleanup by rewriting input.
        if status.secureInput || !configuration.sessionActive || !status.accessibility || !status.postAccess {
            return Unmanaged.passUnretained(event)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let key = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = Self.modifiers(event.flags)
        let side = Self.side(key)
        // Aggregate flags plus per-side history handles both Control keys held together.
        let down = side.map { flags.contains($0.group) && !processor.modifiers.isDown($0) }
        let phase: KeyPhase = type == .keyDown ? .down : type == .keyUp ? .up : .flagsChanged
        let normalized = KeyboardEvent(phase, keyCode: key, modifiers: flags,
                                       isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                       modifierSide: side, modifierDown: down)
        let decision = processor.process(normalized)
        var result: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
        switch decision {
        case .passThrough: break
        case .suppress: result = nil
        case .emergencyPause:
            status.emergencyPaused = true
            configureProcessor()
            result = nil
        case .togglePassThrough:
            status.manualPassThrough = processor.manualPassThrough
            configureProcessor()
            result = nil
        case .action(let action, _):
            _ = actions.submit(action, context: configuration.context)
            result = nil
        case let .rewrite(outputKey, outputModifiers, ruleID):
            EventRewriter.apply(to: event, keyCode: outputKey, modifiers: outputModifiers, marker: marker)
            if phase == .down && !normalized.isRepeat && configuration.diagnostics &&
                ProcessInfo.processInfo.systemUptime < diagnosticDeadline {
                recordSequence &+= 1
                records[recordIndex] = DiagnosticRecord(id: recordSequence, rule: ruleID,
                    application: configuration.context.bundleID,
                    microseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
                recordIndex = (recordIndex + 1) % records.count
                diagnosticRevision &+= 1
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1000
        status.maxMicroseconds = max(status.maxMicroseconds, elapsed)
        return result
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
