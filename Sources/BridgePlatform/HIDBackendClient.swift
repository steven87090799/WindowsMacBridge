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
    public var actionStatus: String { actions.status() }
    public var onOwnershipChange: (() -> Void)?
    public private(set) var releasePending = false
    public var hasOwnership: Bool { connection != nil || stoppingConnection != nil }
    private var stoppingConnection: NSXPCConnection?
    private var stopTimeout: DispatchSourceTimer?
    private var stopID: UUID?
    private var connectionFactory: @MainActor () -> NSXPCConnection = {
        NSXPCConnection(machServiceName: HIDService.name, options: .privileged)
    }
    private var stopAcknowledgementTimeout: TimeInterval = 1.5
    public var onScreenshot: ((ScreenshotKind) -> Void)?
    private nonisolated let incomingActions = BoundedActionInbox()
    private let actions = ShortcutActionDispatcher(marker: EventRewriter.generatedEventMarker)
    private var connection: NSXPCConnection?
    private var configuration = HIDConfiguration()
    private var generation: UInt64 = 0
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
        let wasActive = backendActive
        let effectiveEnabled = engine.enabled && active
        let changed = configuration.processID != engine.context.processID || configuration.bundleID != engine.context.bundleID ||
            configuration.generation != engine.generation || configuration.keyboardScope != engine.keyboardScope ||
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
            configuration.sessionActive != engine.sessionActive || configuration.restartToken != engine.restartToken ||
            configuration.deviceInputs != engine.deviceInputs || backendActive != active
        if changed { generation = engine.generation; actionEpoch &+= 1; actions.cancelPending() }
        backendActive = active
        configuration.enabled = effectiveEnabled
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
        configuration.isBrowser = engine.context.isBrowser; configuration.generation = generation
        configuration.actionGeneration = actionEpoch
        configuration.restartToken = engine.restartToken
        _ = actions.update(context: configuration.context, enabled: configuration.enabled && !status.manualPassThrough,
                           finderEnabled: configuration.finderEnabled,
                           finderPermanentDeleteEnabled: configuration.finderPermanentDeleteEnabled,
                           epoch: actionEpoch)
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
    public func stop() { started = false; timer?.invalidate(); timer = nil; backendActive = false; disconnect() }
    public func requestInputAccess() {
        guard backendActive, let proxy = connection?.remoteObjectProxy as? HIDHelperProtocol else { return }
        proxy.requestInputAccess { _ in }
    }
    /// New input ownership is gated until the old helper confirms physical close and virtual teardown.
    public func releaseOwnership() { backendActive = false; configuration.enabled = false; disconnect() }
    private func disconnect() {
        actions.cancelPending(disable: true)
        timer?.invalidate(); timer = nil
        guard let old = connection else { inFlight = false; return }
        connection = nil; inFlight = false
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
        let proxy = old.remoteObjectProxyWithErrorHandler { _ in } as? HIDHelperProtocol
        proxy?.stop { [weak self, weak old] in
            Task { @MainActor in
                guard let self, let old, self.stopID == id, self.stoppingConnection === old else { return }
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
            next.resume(); connection = next
        }
        guard let connection, let data = try? JSONEncoder().encode(configuration), data.count <= 8192 else { return }
        sentAt = now; inFlight = true
        let sentGeneration = generation
        let sentActionEpoch = actionEpoch
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self, weak connection] _ in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.disconnect(); self.retryAt = ProcessInfo.processInfo.systemUptime + 2
                self.status.state = "Helper 未安裝、尚未核准或 App 簽章與安裝版本不符"
            }
        } as? HIDHelperProtocol
        proxy?.configure(data) { [weak self, weak connection] data in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.inFlight = false
                guard self.backendActive, sentGeneration == self.generation, sentActionEpoch == self.actionEpoch else { self.tick(); return }
                guard data.count <= 16384, let status = try? JSONDecoder().decode(HIDStatus.self, from: data),
                      status.version == HIDService.protocolVersion, status.devices.count <= 16,
                      status.devices.allSatisfy({ $0.identity.utf8.count <= 128 && $0.product.utf8.count <= 256 }) else { self.disconnect(); return }
                self.status = status
                _ = self.actions.update(context: self.configuration.context,
                    enabled: self.configuration.enabled && !status.manualPassThrough && !status.emergencyPaused,
                    finderEnabled: self.configuration.finderEnabled,
                    finderPermanentDeleteEnabled: self.configuration.finderPermanentDeleteEnabled,
                    epoch: self.actionEpoch)
                if sentGeneration != self.generation { self.tick() }
            }
        }
    }
    public nonisolated func performAction(_ id: String, processID: Int32, generation: UInt64) {
        guard id.utf8.count <= 32, let action = HIDActionCodec.decode(id),
              incomingActions.offer(.init(action: action, processID: processID, generation: generation)) else { return }
        Task { @MainActor [weak self] in self?.drainActions() }
    }
    private func drainActions() {
        while let entry = incomingActions.pop() {
            guard backendActive, configuration.enabled, !releasePending, configuration.layoutSupported,
                  !status.manualPassThrough, !status.emergencyPaused,
                  actionEpoch == entry.generation, configuration.processID == entry.processID else { continue }
            if case .screenshot(let kind) = entry.action { onScreenshot?(kind) }
            else { _ = actions.submit(entry.action, context: configuration.context) }
        }
    }
}
