import Foundation
import HIDProtocol
import BridgeCore

/// NSXPCConnection retains its exported object. Keep the controller weak so a pending
/// stop acknowledgement cannot form controller -> connection -> controller ownership.
private final class HIDControllerReceiver: NSObject, HIDControllerProtocol, @unchecked Sendable {
    private weak var controller: HIDBackendClient?
    private let identity: UUID
    init(_ controller: HIDBackendClient, identity: UUID) { self.controller = controller; self.identity = identity }
    func receiveStatus(_ data: Data, generation: UInt64) {
        Task { @MainActor [weak controller, identity] in controller?.acceptStatus(data, generation: generation, identity: identity) }
    }
    func performAction(_ id: String, processID: Int32, generation: UInt64) {
        controller?.performAction(id, processID: processID, generation: generation)
    }
}

/// How a capture lease ended. Only the first three prove that the helper no
/// longer holds a physical keyboard; the others leave the release state unknown.
public enum HIDReleaseOutcome: Equatable, Sendable {
    /// The owning lease's stop reply arrived (DeviceCapture closed devices first).
    case acknowledged
    /// The lease never carried a configure request, so it never owned capture.
    case neverOwned
    /// The helper process is gone (exit event, ESRCH or a reused PID), so the
    /// kernel closed its IOHID handles.
    case helperExited
    /// The helper is alive but did not answer the stop before the deadline.
    case timedOut
    /// XPC failed (invalidation, interruption, proxy error) before an answer and
    /// the helper was not confirmed gone by the deadline.
    case transportLost
    public var confirmsRelease: Bool { self == .acknowledged || self == .neverOwned || self == .helperExited }
}

/// Confirms helper death without trusting XPC transport loss. Injectable for tests.
public struct HIDHelperLiveness: Sendable {
    public var startTime: @Sendable (pid_t) -> UInt64?
    public var isGone: @Sendable (pid_t, UInt64?) -> Bool
    /// Arms a one-shot exit notification; returns a cancel action.
    public var watchExit: @MainActor (pid_t, @escaping @MainActor () -> Void) -> (() -> Void)
    public init(startTime: @escaping @Sendable (pid_t) -> UInt64?, isGone: @escaping @Sendable (pid_t, UInt64?) -> Bool,
                watchExit: @escaping @MainActor (pid_t, @escaping @MainActor () -> Void) -> (() -> Void)) {
        self.startTime = startTime; self.isGone = isGone; self.watchExit = watchExit
    }
    /// kill(pid, 0) distinguishes "no such process" (ESRCH) from a live root
    /// process (EPERM); kinfo_proc start time detects PID reuse.
    public static let system = HIDHelperLiveness(startTime: { pid in
        var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 0, sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.stride,
              info.kp_proc.p_pid == pid else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return UInt64(start.tv_sec) &* 1_000_000 &+ UInt64(start.tv_usec)
    }, isGone: { pid, birth in
        guard pid > 0 else { return false }
        if kill(pid, 0) != 0 && errno == ESRCH { return true }
        guard let birth else { return false }
        var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.stride else { return false }
        if info.kp_proc.p_pid != pid { return true }
        let start = info.kp_proc.p_un.__p_starttime
        return UInt64(start.tv_sec) &* 1_000_000 &+ UInt64(start.tv_usec) != birth
    }, watchExit: { pid, handler in
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.resume()
        return { source.cancel() }
    })
}

/// One XPC connection and what it may have done. Only the owner mutates it.
private final class HIDLease {
    let connection: NSXPCConnection
    let identity = UUID()
    /// A configure request was sent: the helper may have seized devices for it.
    var configureSent = false
    var helperPID: pid_t = 0
    var helperBirth: UInt64?
    init(_ connection: NSXPCConnection) { self.connection = connection }
}

// Cleanup has no actor-bound work: cancel owned deadlines and invalidate IPC.
// The owner mutates this holder on MainActor; final destruction is race-free.
private final class HIDConnectionLifetime: @unchecked Sendable {
    var active: HIDLease?, stopping: HIDLease?, permissionConnection: NSXPCConnection?
    var requestTimeout: DispatchWorkItem?, permissionTimeout: DispatchWorkItem?
    var stopTimeout: DispatchSourceTimer?
    var cancelExitWatch: (() -> Void)?
    deinit {
        requestTimeout?.cancel(); permissionTimeout?.cancel(); stopTimeout?.cancel(); cancelExitWatch?()
        for peer in [active?.connection, stopping?.connection, permissionConnection] {
            peer?.invalidationHandler = nil; peer?.interruptionHandler = nil; peer?.invalidate()
        }
    }
}
@MainActor public final class HIDBackendClient: NSObject, HIDControllerProtocol {
    private let lifetime = HIDConnectionLifetime()
    public private(set) var status = HIDStatus()
    public var onOwnershipChange: (() -> Void)?
    /// A stop is in flight: the helper may still own a physical keyboard.
    public private(set) var releasePending = false
    /// A lease ended without proof of release (`HIDReleaseOutcome.confirmsRelease`
    /// false). Latched: no acknowledgement, late reply or new connection clears it;
    /// only an explicit engine restart (`clearUnconfirmedRelease`) does.
    public private(set) var releaseUnconfirmed = false
    /// Outcome of the most recent lease that may have owned capture.
    public private(set) var lastReleaseOutcome: HIDReleaseOutcome?
    public func clearUnconfirmedRelease() { releaseUnconfirmed = false }
    private let liveness: HIDHelperLiveness
    private var verifiedStatusAt: TimeInterval?
    private var permissionProbeID: UUID?
    private var permissionConnection: NSXPCConnection? { get { lifetime.permissionConnection } set { lifetime.permissionConnection = newValue } }
    private var permissionTimeout: DispatchWorkItem? { get { lifetime.permissionTimeout } set { lifetime.permissionTimeout = newValue } }
    private var permissionReply: ((Bool?) -> Void)?
    public var hasFreshVerifiedStatus: Bool {
        backendActive && configuration.enabled && connection != nil && !releasePending &&
            verifiedStatusAt != nil
    }
    public var hasOwnership: Bool { lifetime.active != nil || lifetime.stopping != nil }
    private var stopTimeout: DispatchSourceTimer? { get { lifetime.stopTimeout } set { lifetime.stopTimeout = newValue } }
    private var stopID: UUID?
    /// Transport failed before the stop reply; resolution waits for helper exit or the deadline.
    private var stopTransportLost = false
    private var connectionFactory: @MainActor () -> NSXPCConnection = {
        NSXPCConnection(machServiceName: HIDService.name, options: .privileged)
    }
    /// DeviceCapture replies after closing devices and VirtualHID teardown.
    private var stopAcknowledgementTimeout: TimeInterval = 3
    public var onScreenshot: ((ScreenshotKind) -> Void)?
    private var connection: NSXPCConnection? { lifetime.active?.connection }
    private var connectionIdentity: UUID? { lifetime.active?.identity }
    private var configuration = HIDConfiguration()
    private var generation: UInt64 = 0
    private var hostGeneration: UInt64 = 0
    private var actionEpoch: UInt64 = 0
    private var backendActive = false
    private var started = false
    private var requestTimeout: DispatchWorkItem? { get { lifetime.requestTimeout } set { lifetime.requestTimeout = newValue } }
    private var inFlight = false
    private var sentAt: Double = 0
    public override init() { liveness = .system; super.init() }
    public init(connectionFactory: @escaping @MainActor () -> NSXPCConnection,
                stopAcknowledgementTimeout: TimeInterval = 3, liveness: HIDHelperLiveness = .system) {
        self.connectionFactory = connectionFactory
        self.stopAcknowledgementTimeout = stopAcknowledgementTimeout.isFinite && stopAcknowledgementTimeout > 0 ? min(3, stopAcknowledgementTimeout) : 3
        self.liveness = liveness
        super.init()
    }
    public func start() {
        guard !started else { return }
        started = true
        if backendActive && configuration.enabled { tick() }
    }
    public func update(_ engine: EngineConfiguration, active: Bool) {
        let previous = configuration
        let wasActive = backendActive
        let effectiveEnabled = engine.enabled && active
        let changed = configuration.processID != engine.context.processID || configuration.bundleID != engine.context.bundleID ||
            hostGeneration != engine.generation || configuration.keyboardScope != engine.keyboardScope ||
            configuration.transportOnly != engine.destinationSemantics ||
            configuration.mode != engine.context.mode || configuration.isBrowser != engine.context.isBrowser ||
            configuration.enabled != effectiveEnabled ||
            configuration.layoutSupported != engine.layoutSupported || configuration.finderEnabled != engine.finderEnabled ||
            configuration.finderPermanentDeleteEnabled != engine.finderPermanentDeleteEnabled ||
            configuration.textNavigationEnabled != engine.textNavigationEnabled ||
            configuration.altF4Enabled != engine.altF4Enabled ||
            configuration.windowsKeyModifier != engine.windowsKeyModifier ||
            configuration.macBookFnControlSwap != engine.macBookFnControlSwap ||
            configuration.winRunEnabled != engine.winRunEnabled ||
            configuration.winSettingsEnabled != engine.winSettingsEnabled ||
            configuration.winTaskViewEnabled != engine.winTaskViewEnabled ||
            configuration.finderBrightnessEnterEnabled != engine.finderBrightnessEnterEnabled ||
            configuration.screenshotEnabled != engine.screenshotEnabled || configuration.printScreenBehavior != engine.printScreenBehavior ||
            configuration.sessionActive != engine.sessionActive || configuration.restartToken != engine.restartToken ||
            configuration.deviceInputs != engine.deviceInputs || backendActive != active
        if changed { actionEpoch &+= 1; verifiedStatusAt = nil }
        hostGeneration = engine.generation
        backendActive = active
        configuration.enabled = effectiveEnabled
        configuration.transportOnly = engine.destinationSemantics
        configuration.sessionActive = engine.sessionActive; configuration.layoutSupported = engine.layoutSupported
        configuration.finderEnabled = engine.finderEnabled; configuration.processID = engine.context.processID
        configuration.finderPermanentDeleteEnabled = engine.finderPermanentDeleteEnabled
        configuration.textNavigationEnabled = engine.textNavigationEnabled
        configuration.altF4Enabled = engine.altF4Enabled
        configuration.windowsKeyModifier = engine.windowsKeyModifier
        configuration.macBookFnControlSwap = engine.macBookFnControlSwap
        configuration.winRunEnabled = engine.winRunEnabled
        configuration.winSettingsEnabled = engine.winSettingsEnabled
        configuration.winTaskViewEnabled = engine.winTaskViewEnabled
        configuration.keyboardScope = engine.keyboardScope
        configuration.deviceInputs = engine.deviceInputs
        configuration.finderBrightnessEnterEnabled = engine.finderBrightnessEnterEnabled
        configuration.screenshotEnabled = engine.screenshotEnabled
        configuration.printScreenBehavior = engine.printScreenBehavior
        configuration.diagnostics = engine.diagnostics
        configuration.bundleID = engine.context.bundleID; configuration.mode = engine.context.mode
        configuration.isBrowser = engine.context.isBrowser; configuration.generation = engine.generation
        configuration.actionGeneration = actionEpoch
        configuration.restartToken = engine.restartToken
        if configuration.transportOnly && previous.sameCapturePolicy(as: configuration) {
            configuration.generation = generation
        } else { generation = engine.generation; configuration.generation = generation }
        if !active || !effectiveEnabled {
            if wasActive || connection != nil {
                disconnect()
            }
        } else if started && changed { tick() }
    }
    public func stop() {
        if let id = permissionProbeID { finishPermissionProbe(id, grant: nil) }
        started = false; backendActive = false; disconnect()
    }
    public func requestInputAccess() {
        checkInputAccess(request: true) { _ in }
    }
    /// Setup must work before AX/backend activation. A read-only endpoint uses
    /// no capture configuration and cannot replace the helper's keyboard lease.
    public func checkInputAccess(request: Bool = false, reply: @escaping (Bool?) -> Void) {
        guard permissionProbeID == nil else { reply(nil); return }
        let id = UUID(); permissionProbeID = id; permissionReply = reply
        let probe = connection ?? connectionFactory()
        if connection == nil {
            permissionConnection = probe
            probe.remoteObjectInterface = NSXPCInterface(with: HIDHelperProtocol.self)
            probe.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.finishPermissionProbe(id, grant: nil) } }
            probe.interruptionHandler = probe.invalidationHandler
            probe.resume()
        }
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finishPermissionProbe(id, grant: nil) }
        }
        permissionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        guard let proxy = probe.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] _ in
            Task { @MainActor in self?.finishPermissionProbe(id, grant: nil) }
        }) as? HIDHelperProtocol else { finishPermissionProbe(id, grant: nil); return }
        let check: @MainActor @Sendable () -> Void = { [weak self] in
            guard self?.permissionProbeID == id else { return }
            proxy.checkInputAccess { @Sendable grant in
                Task { @MainActor in self?.finishPermissionProbe(id, grant: grant) }
            }
        }
        if request { proxy.requestInputAccess { @Sendable _ in Task { @MainActor in check() } } }
        else { check() }
    }
    private func finishPermissionProbe(_ id: UUID, grant: Bool?) {
        guard permissionProbeID == id else { return }
        permissionProbeID = nil
        permissionTimeout?.cancel(); permissionTimeout = nil
        let old = permissionConnection; permissionConnection = nil
        let reply = permissionReply; permissionReply = nil
        old?.invalidationHandler = nil; old?.interruptionHandler = nil; old?.invalidate()
        reply?(grant)
    }
    /// New input ownership is gated until the old helper confirms physical close and virtual teardown.
    public func releaseOwnership() { backendActive = false; configuration.enabled = false; disconnect() }
    /// Retires the active lease. A lease that may own capture keeps
    /// `releasePending` until its outcome is known; XPC transport loss alone is
    /// never treated as proof that the helper closed the seized devices.
    private func disconnect(transportLost: Bool = false) {
        verifiedStatusAt = nil
        requestTimeout?.cancel(); requestTimeout = nil; inFlight = false
        guard let lease = lifetime.active else { return }
        lifetime.active = nil
        lease.connection.invalidationHandler = nil; lease.connection.interruptionHandler = nil
        guard lease.configureSent else {
            // Never asked to capture: nothing to release.
            lease.connection.invalidate()
            return
        }
        guard lifetime.stopping == nil else {
            // Cannot track two stops at once (prevented by the gate); never drop one silently.
            lease.connection.invalidate()
            conclude(.transportLost, notify: true)
            return
        }
        lifetime.stopping = lease; releasePending = true; stopTransportLost = transportLost
        let id = UUID(); stopID = id
        onOwnershipChange?()
        let timeout = DispatchSource.makeTimerSource(queue: .main)
        timeout.schedule(deadline: .now() + stopAcknowledgementTimeout)
        timeout.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.stopDeadlineReached(id) }
        }
        stopTimeout = timeout; timeout.resume()
        if lease.helperPID > 0 {
            // Event-driven confirmation of helper death; no polling.
            lifetime.cancelExitWatch = liveness.watchExit(lease.helperPID) { [weak self] in
                self?.resolveStop(id, .helperExited)
            }
        }
        lease.connection.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.stopTransportFailed(id) } }
        lease.connection.interruptionHandler = lease.connection.invalidationHandler
        let proxy = lease.connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in self?.stopTransportFailed(id) }
        } as? HIDHelperProtocol
        proxy?.stop { @Sendable [weak self] in
            Task { @MainActor in self?.resolveStop(id, .acknowledged) }
        }
    }
    /// XPC failed before the reply. Keep the gate closed; the helper-exit watch or
    /// the deadline (with a final liveness check) decides the outcome.
    private func stopTransportFailed(_ id: UUID) {
        guard stopID == id else { return }
        stopTransportLost = true
        if let lease = lifetime.stopping, lease.helperPID > 0, liveness.isGone(lease.helperPID, lease.helperBirth) {
            resolveStop(id, .helperExited)
        }
    }
    private func stopDeadlineReached(_ id: UUID) {
        guard stopID == id, let lease = lifetime.stopping else { return }
        if lease.helperPID > 0, liveness.isGone(lease.helperPID, lease.helperBirth) {
            resolveStop(id, .helperExited)
        } else {
            resolveStop(id, stopTransportLost ? .transportLost : .timedOut)
        }
    }
    private func resolveStop(_ id: UUID, _ outcome: HIDReleaseOutcome) {
        // A late reply, exit event or deadline for a retired stop is ignored.
        guard stopID == id else { return }
        stopTimeout?.cancel(); stopTimeout = nil; stopID = nil
        lifetime.cancelExitWatch?(); lifetime.cancelExitWatch = nil
        let old = lifetime.stopping; lifetime.stopping = nil
        old?.connection.invalidationHandler = nil; old?.connection.interruptionHandler = nil; old?.connection.invalidate()
        releasePending = false; stopTransportLost = false
        conclude(outcome, notify: true)
    }
    private func conclude(_ outcome: HIDReleaseOutcome, notify: Bool) {
        lastReleaseOutcome = outcome
        status = HIDStatus()
        // An ACK proves only this lease's release, never an earlier unknown one:
        // the helper answers a non-owner's stop without stopping capture.
        if !outcome.confirmsRelease { releaseUnconfirmed = true }
        switch outcome {
        case .acknowledged, .neverOwned: break
        case .helperExited: status.state = "背景元件已結束；系統已收回實體鍵盤。"
        case .timedOut: status.state = "停止未獲確認；已銷毀舊連線。確認鍵盤正常後按「恢復／重啟引擎」。"
        case .transportLost: status.state = "背景元件連線中斷且未確認釋放鍵盤；確認鍵盤正常後按「恢復／重啟引擎」。"
        }
        if notify { onOwnershipChange?() }
    }
    /// The helper's PID is known once it has answered; its start time detects PID reuse.
    private func recordHelper(_ lease: HIDLease) {
        let pid = lease.connection.processIdentifier
        guard pid > 0, lease.helperPID != pid else { return }
        lease.helperPID = pid; lease.helperBirth = liveness.startTime(pid)
    }
    fileprivate func acceptStatus(_ data: Data, generation: UInt64, identity: UUID) {
        guard connectionIdentity == identity, backendActive, !releasePending,
              generation == configuration.generation, data.count <= 16384,
              let value = try? JSONDecoder().decode(HIDStatus.self, from: data), value.version == HIDService.protocolVersion,
              value.devices.count <= 16, value.devices.allSatisfy({ $0.identity.utf8.count <= 128 && $0.product.utf8.count <= 256 }) else { return }
        status = value; verifiedStatusAt = ProcessInfo.processInfo.systemUptime; onOwnershipChange?()
    }
    public nonisolated func receiveStatus(_ data: Data, generation: UInt64) {}
    private func tick() {
        guard backendActive, configuration.enabled, !releasePending else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if inFlight {
            if now - sentAt > 1 { disconnect(); status.state = "Helper 回應逾時；已停止擷取" }
            return
        }

        if lifetime.active == nil {
            let next = connectionFactory()
            let lease = HIDLease(next)
            let identity = lease.identity
            next.remoteObjectInterface = NSXPCInterface(with: HIDHelperProtocol.self)
            next.exportedInterface = NSXPCInterface(with: HIDControllerProtocol.self)
            next.exportedObject = HIDControllerReceiver(self, identity: identity)
            // Losing an active lease is not proof of release: run the stop state machine.
            next.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in
                guard let self, self.connectionIdentity == identity else { return }
                self.disconnect(transportLost: true)
            } }
            next.interruptionHandler = next.invalidationHandler
            lifetime.active = lease; next.resume()
        }
        // Legacy per-device translation cannot authorize source-side AX/Clipboard work.
        // Preserve the requested UI policy; restrict only the capture worker's capabilities.
        var captureConfiguration = configuration
        captureConfiguration.finderEnabled = false; captureConfiguration.finderPermanentDeleteEnabled = false
        captureConfiguration.altF4Enabled = false; captureConfiguration.finderBrightnessEnterEnabled = false
        captureConfiguration.screenshotEnabled = false
        captureConfiguration.winSettingsEnabled = false
        guard let lease = lifetime.active, let data = try? JSONEncoder().encode(captureConfiguration), data.count <= 8192 else { return }
        let connection = lease.connection, connectionIdentity = lease.identity
        sentAt = now; inFlight = true
        lease.configureSent = true
        requestTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in MainActor.assumeIsolated {
            guard let self, self.connectionIdentity == connectionIdentity, self.inFlight else { return }
            self.disconnect(); self.status.state = "進階背景元件回應逾時；請重新啟動引擎。"
            self.onOwnershipChange?()
        } }
        requestTimeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timeout)
        let sentGeneration = generation
        let sentActionEpoch = actionEpoch
        let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.connectionIdentity == connectionIdentity else { return }
                self.disconnect(transportLost: true)
                if !self.releasePending && !self.releaseUnconfirmed {
                    self.status.state = "進階背景元件未安裝、尚未核准或安裝版本不符"
                    self.onOwnershipChange?()
                }
            }
        } as? HIDHelperProtocol
        proxy?.configure(data) { @Sendable [weak self] data in
            Task { @MainActor in
                guard let self, self.connectionIdentity == connectionIdentity else { return }
                self.inFlight = false; self.requestTimeout?.cancel(); self.requestTimeout = nil
                if let active = self.lifetime.active, active.identity == connectionIdentity { self.recordHelper(active) }
                guard self.backendActive, sentGeneration == self.generation, sentActionEpoch == self.actionEpoch else { self.tick(); return }
                guard data.count <= 16384, let status = try? JSONDecoder().decode(HIDStatus.self, from: data),
                      status.version == HIDService.protocolVersion, status.devices.count <= 16,
                      status.devices.allSatisfy({ $0.identity.utf8.count <= 128 && $0.product.utf8.count <= 256 }) else { self.disconnect(); return }
                self.status = status
                self.verifiedStatusAt = ProcessInfo.processInfo.systemUptime
                self.onOwnershipChange?()
                if sentGeneration != self.generation { self.tick() }
            }
        }
    }
    public nonisolated func performAction(_ id: String, processID: Int32, generation: UInt64) {
        // A helper action has no local-delivery authority. Reject synchronously without
        // allocating a Task, enqueuing work, touching AX or modifying Clipboard.
    }
}
