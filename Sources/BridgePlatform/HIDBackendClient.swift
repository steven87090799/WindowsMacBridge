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

// Cleanup has no actor-bound work: cancel owned deadlines and invalidate IPC.
// The owner mutates this holder on MainActor; final destruction is race-free.
private final class HIDConnectionLifetime: @unchecked Sendable {
    var connection: NSXPCConnection?, stoppingConnection: NSXPCConnection?, permissionConnection: NSXPCConnection?
    var requestTimeout: DispatchWorkItem?, permissionTimeout: DispatchWorkItem?
    var stopTimeout: DispatchSourceTimer?
    deinit {
        requestTimeout?.cancel(); permissionTimeout?.cancel(); stopTimeout?.cancel()
        for peer in [connection, stoppingConnection, permissionConnection] {
            peer?.invalidationHandler = nil; peer?.interruptionHandler = nil; peer?.invalidate()
        }
    }
}
@MainActor public final class HIDBackendClient: NSObject, HIDControllerProtocol {
    private let lifetime = HIDConnectionLifetime()
    public private(set) var status = HIDStatus()
    public var onOwnershipChange: (() -> Void)?
    public private(set) var releasePending = false
    /// A stop request timed out: the lease was invalidated, but the helper never
    /// confirmed that the keyboard was released. Never inferred from a timeout;
    /// cleared by an acknowledgement or an explicit engine restart only.
    public private(set) var releaseUnconfirmed = false
    public func clearUnconfirmedRelease() { releaseUnconfirmed = false }
    private var verifiedStatusAt: TimeInterval?
    private var permissionProbeID: UUID?
    private var permissionConnection: NSXPCConnection? { get { lifetime.permissionConnection } set { lifetime.permissionConnection = newValue } }
    private var permissionTimeout: DispatchWorkItem? { get { lifetime.permissionTimeout } set { lifetime.permissionTimeout = newValue } }
    private var permissionReply: ((Bool?) -> Void)?
    public var hasFreshVerifiedStatus: Bool {
        backendActive && configuration.enabled && connection != nil && !releasePending &&
            verifiedStatusAt != nil
    }
    public var hasOwnership: Bool { connection != nil || stoppingConnection != nil }
    private var stoppingConnection: NSXPCConnection? { get { lifetime.stoppingConnection } set { lifetime.stoppingConnection = newValue } }
    private var stopTimeout: DispatchSourceTimer? { get { lifetime.stopTimeout } set { lifetime.stopTimeout = newValue } }
    private var stopID: UUID?
    private var connectionFactory: @MainActor () -> NSXPCConnection = {
        NSXPCConnection(machServiceName: HIDService.name, options: .privileged)
    }
    private var stopAcknowledgementTimeout: TimeInterval = 1.5
    public var onScreenshot: ((ScreenshotKind) -> Void)?
    private var connection: NSXPCConnection? { get { lifetime.connection } set { lifetime.connection = newValue } }
    private var connectionIdentity: UUID?
    private var configuration = HIDConfiguration()
    private var generation: UInt64 = 0
    private var hostGeneration: UInt64 = 0
    private var actionEpoch: UInt64 = 0
    private var backendActive = false
    private var started = false
    private var requestTimeout: DispatchWorkItem? { get { lifetime.requestTimeout } set { lifetime.requestTimeout = newValue } }
    private var inFlight = false
    private var sentAt: Double = 0
    public override init() { super.init() }
    public init(connectionFactory: @escaping @MainActor () -> NSXPCConnection,
                stopAcknowledgementTimeout: TimeInterval = 1.5) {
        self.connectionFactory = connectionFactory
        self.stopAcknowledgementTimeout = stopAcknowledgementTimeout.isFinite && stopAcknowledgementTimeout > 0 ? min(1.5, stopAcknowledgementTimeout) : 1.5
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
    private func disconnect() {
        verifiedStatusAt = nil
        requestTimeout?.cancel(); requestTimeout = nil
        guard let old = connection else { inFlight = false; return }
        connection = nil; connectionIdentity = nil; inFlight = false
        guard stoppingConnection == nil else { old.invalidate(); return }
        stoppingConnection = old; releasePending = true
        let id = UUID(); stopID = id
        onOwnershipChange?()
        let timeout = DispatchSource.makeTimerSource(queue: .main)
        timeout.schedule(deadline: .now() + stopAcknowledgementTimeout)
        timeout.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.stopID == id else { return }
                self.stopTimeout?.cancel(); self.stopTimeout = nil
                // Invalidation retires the authenticated ownership lease at the
                // service, but a stalled helper may still hold the keyboard. The
                // pending flag ends here; the owner fails closed on releaseUnconfirmed.
                self.finishStop(id, acknowledged: false, timedOut: true)
            }
        }
        stopTimeout = timeout; timeout.resume()
        old.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.finishStop(id, acknowledged: false) } }
        old.interruptionHandler = old.invalidationHandler
        let proxy = old.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in self?.finishStop(id, acknowledged: false) }
        } as? HIDHelperProtocol
        proxy?.stop { @Sendable [weak self] in
            Task { @MainActor in
                self?.finishStop(id, acknowledged: true)
            }
        }
    }
    private func finishStop(_ id: UUID, acknowledged: Bool, timedOut: Bool = false) {
        guard stopID == id else { return }
        stopTimeout?.cancel(); stopTimeout = nil; stopID = nil
        let old = stoppingConnection; stoppingConnection = nil
        old?.invalidationHandler = nil; old?.interruptionHandler = nil; old?.invalidate()
        releasePending = false; status = HIDStatus()
        if acknowledged { releaseUnconfirmed = false }
        // Invalidation/transport loss means the helper connection is gone; the
        // service stops capture on invalidation. Only a live, silent helper latches.
        if timedOut { releaseUnconfirmed = true }
        if !acknowledged {
            status.state = timedOut ? "停止未獲確認；已銷毀舊連線。確認鍵盤正常後按「恢復／重啟引擎」。"
                                    : "背景元件連線已結束；擷取已交還系統。"
        }
        onOwnershipChange?()
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

        if connection == nil {
            let next = connectionFactory()
            next.remoteObjectInterface = NSXPCInterface(with: HIDHelperProtocol.self)
            next.exportedInterface = NSXPCInterface(with: HIDControllerProtocol.self)
            let identity = UUID()
            next.exportedObject = HIDControllerReceiver(self, identity: identity)
            next.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in
                guard let self, self.connectionIdentity == identity else { return }
                self.disconnect(); self.status.state = "進階背景元件已斷線；實體輸入已交還系統。"
                self.onOwnershipChange?()
            } }
            next.interruptionHandler = next.invalidationHandler
            connectionIdentity = identity; next.resume(); connection = next
        }
        // Legacy per-device translation cannot authorize source-side AX/Clipboard work.
        // Preserve the requested UI policy; restrict only the capture worker's capabilities.
        var captureConfiguration = configuration
        captureConfiguration.finderEnabled = false; captureConfiguration.finderPermanentDeleteEnabled = false
        captureConfiguration.altF4Enabled = false; captureConfiguration.finderBrightnessEnterEnabled = false
        captureConfiguration.screenshotEnabled = false
        captureConfiguration.winSettingsEnabled = false
        guard let connection, let connectionIdentity, let data = try? JSONEncoder().encode(captureConfiguration), data.count <= 8192 else { return }
        sentAt = now; inFlight = true
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
                self.disconnect()
                self.status.state = "進階背景元件未安裝、尚未核准或安裝版本不符"
                self.onOwnershipChange?()
            }
        } as? HIDHelperProtocol
        proxy?.configure(data) { @Sendable [weak self] data in
            Task { @MainActor in
                guard let self, self.connectionIdentity == connectionIdentity else { return }
                self.inFlight = false; self.requestTimeout?.cancel(); self.requestTimeout = nil
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
