import Foundation
import HIDProtocol
import BridgeCore

public enum InputBackend: String, Codable, CaseIterable, Sendable {
    case deviceHID, eventTap
    public var title: String { self == .deviceHID ? "指定鍵盤 HID 後端（需要安裝 helper）" : "CGEventTap 快捷鍵預覽" }
}

@MainActor public final class HIDBackendClient: NSObject, HIDControllerProtocol {
    public private(set) var status = HIDStatus()
    public var actionStatus: String { actions.status() }
    private let actions = ShortcutActionDispatcher(marker: Int64.random(in: 1...Int64.max))
    private var connection: NSXPCConnection?
    private var configuration = HIDConfiguration()
    private var generation: UInt64 = 0
    private var backendActive = false
    private var started = false
    private var timer: Timer?
    private var inFlight = false
    private var sentAt: Double = 0, retryAt: Double = 0
    public override init() { super.init() }
    public func start() {
        guard !started else { return }
        started = true
        if backendActive { startHeartbeat() }
    }
    private func startHeartbeat() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    public func update(_ engine: EngineConfiguration, active: Bool) {
        let wasActive = backendActive
        let effectiveEnabled = engine.enabled && active && engine.keyboardScope == .builtInAndApple834
        let changed = configuration.processID != engine.context.processID || configuration.bundleID != engine.context.bundleID ||
            configuration.mode != engine.context.mode || configuration.isBrowser != engine.context.isBrowser ||
            configuration.enabled != effectiveEnabled ||
            configuration.layoutSupported != engine.layoutSupported || configuration.finderEnabled != engine.finderEnabled ||
            configuration.sessionActive != engine.sessionActive || configuration.restartToken != engine.restartToken || backendActive != active
        if changed { generation &+= 1; actions.cancelPending() }
        backendActive = active
        configuration.enabled = effectiveEnabled
        configuration.sessionActive = engine.sessionActive; configuration.layoutSupported = engine.layoutSupported
        configuration.finderEnabled = engine.finderEnabled; configuration.processID = engine.context.processID
        configuration.diagnostics = engine.diagnostics
        configuration.bundleID = engine.context.bundleID; configuration.mode = engine.context.mode
        configuration.isBrowser = engine.context.isBrowser; configuration.generation = generation
        configuration.restartToken = engine.restartToken
        _ = actions.update(context: configuration.context, enabled: configuration.enabled && !status.manualPassThrough,
                           finderEnabled: configuration.finderEnabled, epoch: generation)
        if !active {
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
    private func disconnect() {
        actions.cancelPending(disable: true)
        if let proxy = connection?.remoteObjectProxy as? HIDHelperProtocol { proxy.stop {} }
        connection?.invalidate(); connection = nil; inFlight = false
        status = HIDStatus()
    }
    private func tick() {
        guard backendActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if inFlight {
            if now - sentAt > 1 { connection?.invalidate(); connection = nil; inFlight = false; retryAt = now + 2; status.state = "Helper 回應逾時；已停止擷取" }
            return
        }
        guard now >= retryAt else { return }
        if connection == nil {
            let next = NSXPCConnection(machServiceName: HIDService.name, options: .privileged)
            next.remoteObjectInterface = NSXPCInterface(with: HIDHelperProtocol.self)
            next.exportedInterface = NSXPCInterface(with: HIDControllerProtocol.self)
            next.exportedObject = self
            next.resume(); connection = next
        }
        guard let connection, let data = try? JSONEncoder().encode(configuration) else { return }
        sentAt = now; inFlight = true
        let sentGeneration = generation
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
                guard data.count <= 4096, let status = try? JSONDecoder().decode(HIDStatus.self, from: data),
                      status.version == HIDService.protocolVersion else { self.disconnect(); return }
                self.status = status
                _ = self.actions.update(context: self.configuration.context,
                    enabled: self.configuration.enabled && !status.manualPassThrough && !status.emergencyPaused,
                    finderEnabled: self.configuration.finderEnabled, epoch: self.generation)
                if sentGeneration != self.generation { self.tick() }
            }
        }
    }
    public nonisolated func performAction(_ id: String, processID: Int32, generation: UInt64) {
        guard id.utf8.count <= 32, let action = HIDActionCodec.decode(id) else { return }
        Task { @MainActor [weak self] in
            guard let self, backendActive, configuration.enabled, configuration.layoutSupported,
                  !status.manualPassThrough, !status.emergencyPaused,
                  self.generation == generation, configuration.processID == processID else { return }
            _ = actions.submit(action, context: configuration.context)
        }
    }
}
