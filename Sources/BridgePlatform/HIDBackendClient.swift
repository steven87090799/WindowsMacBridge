import Foundation
import HIDProtocol
import BridgeCore

/// NSXPCConnection retains its exported object. Keep the controller weak so a pending
/// stop acknowledgement cannot form controller -> connection -> controller ownership.
private final class HIDControllerReceiver: NSObject, HIDControllerProtocol, @unchecked Sendable {
    private weak var controller: HIDBackendClient?
    init(_ controller: HIDBackendClient) { self.controller = controller }
    func performAction(_ id: String, processID: Int32, generation: UInt64) {
        controller?.performAction(id, processID: processID, generation: generation)
    }
}

@MainActor public final class HIDBackendClient: NSObject, HIDControllerProtocol {
    public private(set) var status = HIDStatus()
    public var onOwnershipChange: (() -> Void)?
    public private(set) var releasePending = false
    private var verifiedStatusAt: TimeInterval?
    private var permissionProbeID: UUID?
    private var permissionConnection: NSXPCConnection?
    private var permissionTimeout: DispatchWorkItem?
    private var permissionReply: ((Bool?) -> Void)?
    public var hasFreshVerifiedStatus: Bool {
        backendActive && configuration.enabled && connection != nil && !releasePending &&
            verifiedStatusAt.map { ProcessInfo.processInfo.systemUptime - $0 <= 1 } == true
    }
    public var hasOwnership: Bool { connection != nil || stoppingConnection != nil }
    private var stoppingConnection: NSXPCConnection?
    private var stopTimeout: DispatchSourceTimer?
    private var stopID: UUID?
    private var connectionFactory: @MainActor () -> NSXPCConnection = {
        NSXPCConnection(machServiceName: HIDService.name, options: .privileged)
    }
    private var stopAcknowledgementTimeout: TimeInterval = 1.5
    public var onScreenshot: ((ScreenshotKind) -> Void)?
    private var connection: NSXPCConnection?
    private var connectionIdentity: UUID?
    private var configuration = HIDConfiguration()
    private var generation: UInt64 = 0
    private var hostGeneration: UInt64 = 0
    private var actionEpoch: UInt64 = 0
    private var backendActive = false
    private var started = false
    private var timer: Timer?
    private var inFlight = false
    private var sentAt: Double = 0, retryAt: Double = 0
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
        if backendActive && configuration.enabled { startHeartbeat() }
    }
    private func startHeartbeat() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
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
            if wasActive || timer != nil || connection != nil {
                timer?.invalidate(); timer = nil
                disconnect()
            }
        } else if started {
            startHeartbeat()
            tick()
        }
    }
    public func stop() {
        if let id = permissionProbeID { finishPermissionProbe(id, grant: nil) }
        started = false; timer?.invalidate(); timer = nil; backendActive = false; disconnect()
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
        timer?.invalidate(); timer = nil
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
                // A timeout is no acknowledgement. Keep every new backend stopped.
                self.status.state = "Helper 停止未獲確認；新後端保持停用，請重新啟動 App／helper。"
            }
        }
        stopTimeout = timeout; timeout.resume()
        let proxy = old.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? HIDHelperProtocol
        proxy?.stop { @Sendable [weak self] in
            Task { @MainActor in
                guard let self, self.stopID == id, let old = self.stoppingConnection else { return }
                self.stopTimeout?.cancel(); self.stopTimeout = nil
                self.stopID = nil; self.stoppingConnection = nil; old.invalidate()
                self.releasePending = false; self.status = HIDStatus()
                self.onOwnershipChange?()
            }
        }
    }
    private func tick() {
        guard backendActive, configuration.enabled, !releasePending else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if inFlight {
            if now - sentAt > 1 { disconnect(); retryAt = now + 2; status.state = "Helper 回應逾時；已停止擷取" }
            return
        }
        guard now >= retryAt else { return }
        if connection == nil {
            let next = connectionFactory()
            next.remoteObjectInterface = NSXPCInterface(with: HIDHelperProtocol.self)
            next.exportedInterface = NSXPCInterface(with: HIDControllerProtocol.self)
            next.exportedObject = HIDControllerReceiver(self)
            connectionIdentity = UUID(); next.resume(); connection = next
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
        let sentGeneration = generation
        let sentActionEpoch = actionEpoch
        let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.connectionIdentity == connectionIdentity else { return }
                self.disconnect(); self.retryAt = ProcessInfo.processInfo.systemUptime + 2
                self.status.state = "Helper 未安裝、尚未核准或 App 簽章與安裝版本不符"
            }
        } as? HIDHelperProtocol
        proxy?.configure(data) { @Sendable [weak self] data in
            Task { @MainActor in
                guard let self, self.connectionIdentity == connectionIdentity else { return }
                self.inFlight = false
                guard self.backendActive, sentGeneration == self.generation, sentActionEpoch == self.actionEpoch else { self.tick(); return }
                guard data.count <= 16384, let status = try? JSONDecoder().decode(HIDStatus.self, from: data),
                      status.version == HIDService.protocolVersion, status.devices.count <= 16,
                      status.devices.allSatisfy({ $0.identity.utf8.count <= 128 && $0.product.utf8.count <= 256 }) else { self.disconnect(); return }
                self.status = status
                self.verifiedStatusAt = ProcessInfo.processInfo.systemUptime
                if sentGeneration != self.generation { self.tick() }
            }
        }
    }
    public nonisolated func performAction(_ id: String, processID: Int32, generation: UInt64) {
        // A helper action has no local-delivery authority. Reject synchronously without
        // allocating a Task, enqueuing work, touching AX or modifying Clipboard.
    }
}
