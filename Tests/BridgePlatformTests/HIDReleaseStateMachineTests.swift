import Foundation
import Testing
import BridgeCore
import HIDProtocol
@testable import BridgePlatform

/// In-process fake helper over a real anonymous XPC listener. Stop replies are
/// held until `acknowledge()`; `dropClients()` invalidates the server side.
private final class FakeHelper: NSObject, HIDHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stopReplies: [() -> Void] = []
    private var accepted: [NSXPCConnection] = []
    private var configureCount = 0
    let listener = NSXPCListener.anonymous()
    override init() { super.init(); listener.delegate = self; listener.resume() }
    var configurations: Int { lock.lock(); defer { lock.unlock() }; return configureCount }
    var stopRequests: Int { lock.lock(); defer { lock.unlock() }; return stopReplies.count }
    func acknowledge() { lock.lock(); let replies = stopReplies; stopReplies.removeAll(); lock.unlock(); replies.forEach { $0() } }
    func dropClients() { lock.lock(); let peers = accepted; lock.unlock(); peers.forEach { $0.invalidate() } }
    func shutdown() { acknowledge(); dropClients(); listener.invalidate() }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HIDHelperProtocol.self)
        connection.exportedObject = self
        lock.lock(); accepted.append(connection); lock.unlock()
        connection.resume(); return true
    }
    func configure(_ data: Data, withReply reply: @escaping (Data) -> Void) {
        lock.lock(); configureCount += 1; lock.unlock()
        reply((try? JSONEncoder().encode(HIDStatus())) ?? Data())
    }
    func stop(withReply reply: @escaping () -> Void) { lock.lock(); stopReplies.append(reply); lock.unlock() }
    func requestInputAccess(withReply reply: @escaping (Bool) -> Void) { reply(false) }
    func checkInputAccess(withReply reply: @escaping (Bool) -> Void) { reply(false) }
}

/// Liveness the test controls: whether the helper counts as gone, and a manual exit event.
@MainActor private final class FakeLiveness {
    var gone = false
    var exitHandlers: [@MainActor () -> Void] = []
    var cancelled = 0
    var value: HIDHelperLiveness {
        HIDHelperLiveness(startTime: { _ in 42 }, isGone: { [weak self] _, _ in
            MainActor.assumeIsolated { self?.gone ?? false }
        }, watchExit: { [weak self] _, handler in
            self?.exitHandlers.append(handler)
            return { [weak self] in self?.cancelled += 1 }
        })
    }
    func exit() { gone = true; exitHandlers.forEach { $0() } }
}

@MainActor private func activeConfig(generation: UInt64 = 1) -> EngineConfiguration {
    var config = EngineConfiguration(); config.enabled = true; config.generation = generation
    config.context = .init(processID: .max, bundleID: "test", mode: .macOS)
    return config
}
/// Returns as soon as the condition holds. The bound covers the multi-second XPC
/// stall seen at the start of CI test runs; it never relaxes what is asserted.
@MainActor private func eventually(_ seconds: Double = 60, _ condition: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while !condition(), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

// Serialized: each test drives real XPC on the MainActor; running all of them
// at once starves configure replies on small CI runners.
@MainActor @Suite(.serialized) struct HIDReleaseStateMachineTests {
    private func client(_ helper: FakeHelper, _ liveness: FakeLiveness, timeout: TimeInterval = 3,
                        created: ((NSXPCConnection) -> Void)? = nil) -> HIDBackendClient {
        let client = HIDBackendClient(connectionFactory: {
            let connection = NSXPCConnection(listenerEndpoint: helper.listener.endpoint)
            created?(connection); return connection
        }, stopAcknowledgementTimeout: timeout, liveness: liveness.value)
        // The fake replies at once; only a starved CI MainActor can miss 1.5 s.
        client.configureReplyTimeout = 60
        return client
    }
    /// Configure and wait for the reply so the lease knows the helper PID.
    private func owned(_ client: HIDBackendClient, _ helper: FakeHelper) async throws {
        client.start(); client.update(activeConfig(), active: true)
        try await eventually { helper.configurations > 0 && client.hasFreshVerifiedStatus }
        #expect(client.hasFreshVerifiedStatus)
    }

    @Test func stopAcknowledgementReleasesTheGate() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let client = client(helper, liveness)
        try await owned(client, helper)
        client.releaseOwnership()
        #expect(client.releasePending && !client.releaseUnconfirmed)
        try await eventually { helper.stopRequests > 0 }
        helper.acknowledge()
        try await eventually { !client.releasePending }
        #expect(client.lastReleaseOutcome == .acknowledged && !client.releaseUnconfirmed && liveness.cancelled == 1)
    }
    @Test func stopTimeoutWithLiveHelperFailsClosed() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let client = client(helper, liveness, timeout: 0.2)
        try await owned(client, helper)
        client.releaseOwnership()
        try await eventually { !client.releasePending }
        #expect(client.lastReleaseOutcome == .timedOut && client.releaseUnconfirmed)
    }
    @Test func helperInvalidatingDuringStopIsNotAReleaseUntilTheDeadline() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        // Long enough that a slow runner cannot reach the deadline before the
        // pending check below; the outcome is still decided by the deadline.
        let liveness = FakeLiveness(); let client = client(helper, liveness, timeout: 3)
        try await owned(client, helper)
        client.releaseOwnership()
        try await eventually { helper.stopRequests > 0 }
        helper.dropClients()                       // XPC invalidation before the ACK
        try await Task.sleep(for: .milliseconds(100))
        #expect(client.releasePending, "transport loss alone must keep the gate closed")
        try await eventually { !client.releasePending }
        #expect(client.lastReleaseOutcome == .transportLost && client.releaseUnconfirmed)
    }
    @Test func activeLeaseInvalidationRunsTheStopStateMachine() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let client = client(helper, liveness, timeout: 0.5)
        try await owned(client, helper)
        helper.dropClients()                       // proxy error / invalidation with no stop requested
        try await eventually { client.releasePending || client.releaseUnconfirmed }
        #expect(client.releasePending || client.releaseUnconfirmed)
        try await eventually { !client.releasePending }
        #expect(client.releaseUnconfirmed && client.lastReleaseOutcome == .transportLost)
    }
    @Test func interruptionWithHelperGoneConfirmsReleaseAndWithLiveHelperDoesNot() async throws {
        for helperGone in [true, false] {
            let helper = FakeHelper(); defer { helper.shutdown() }
            let liveness = FakeLiveness()
            var connections: [NSXPCConnection] = []
            let client = client(helper, liveness, timeout: 0.4) { connections.append($0) }
            try await owned(client, helper)
            client.releaseOwnership()
            liveness.gone = helperGone
            connections.last?.interruptionHandler?()
            try await eventually { !client.releasePending }
            #expect(client.lastReleaseOutcome == (helperGone ? .helperExited : .transportLost))
            #expect(client.releaseUnconfirmed == !helperGone)
        }
    }
    @Test func helperExitEventConfirmsReleaseWithoutWaitingForTheDeadline() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let client = client(helper, liveness, timeout: 3)
        try await owned(client, helper)
        client.releaseOwnership()
        #expect(client.releasePending && liveness.exitHandlers.count == 1)
        liveness.exit()
        #expect(!client.releasePending && client.lastReleaseOutcome == .helperExited && !client.releaseUnconfirmed)
    }
    @Test func lateAcknowledgementAfterTimeoutCannotClearTheLatch() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let client = client(helper, liveness, timeout: 0.2)
        try await owned(client, helper)
        client.releaseOwnership()
        try await eventually { !client.releasePending }
        #expect(client.releaseUnconfirmed)
        helper.acknowledge()
        try await Task.sleep(for: .milliseconds(100))
        #expect(client.releaseUnconfirmed && client.lastReleaseOutcome == .timedOut)
    }
    @Test func oldConnectionCallbacksCannotTouchTheNewLease() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness()
        var connections: [NSXPCConnection] = []
        let client = client(helper, liveness) { connections.append($0) }
        try await owned(client, helper)
        let old = connections[0]
        let oldInvalidation = old.invalidationHandler
        client.releaseOwnership()
        let oldStopFailure = old.invalidationHandler
        try await eventually { helper.stopRequests > 0 }
        helper.acknowledge()
        try await eventually { !client.releasePending }
        // New generation, new lease.
        client.update(activeConfig(generation: 2), active: true)
        try await eventually { connections.count == 2 && client.hasFreshVerifiedStatus }
        oldInvalidation?(); oldStopFailure?()
        liveness.exit()                             // exit watch of the retired stop was cancelled
        try await Task.sleep(for: .milliseconds(100))
        #expect(client.hasOwnership && !client.releasePending && !client.releaseUnconfirmed)
        #expect(client.lastReleaseOutcome == .acknowledged)
    }
    @Test func neverConfiguredLeaseHasNothingToRelease() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let client = client(helper, liveness)
        var config = activeConfig(); config.enabled = false
        client.start(); client.update(config, active: true)
        client.releaseOwnership()
        #expect(!client.releasePending && !client.releaseUnconfirmed && helper.stopRequests == 0)
    }

    // Slot-level transitions: the gate BridgeController feeds into RuntimePolicy.
    private func slot(_ helper: FakeHelper, _ liveness: FakeLiveness, timeout: TimeInterval = 3) -> HIDBackendSlot {
        HIDBackendSlot(factory: {
            let client = HIDBackendClient(connectionFactory: { NSXPCConnection(listenerEndpoint: helper.listener.endpoint) },
                                          stopAcknowledgementTimeout: timeout, liveness: liveness.value)
            client.configureReplyTimeout = 60; return client
        })
    }
    private func policy(_ slot: HIDBackendSlot, backend: InputBackend) -> RuntimePolicySnapshot {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true; input.backend = backend
        input.hidReleasePending = slot.releasePending
        var coordinator = RuntimePolicyCoordinator(); return coordinator.transition(input)
    }
    @Test func hidToEventTapKeepsEventTapGatedUntilAcknowledged() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let slot = slot(helper, liveness)
        slot.synchronize(wanted: true); slot.active?.update(activeConfig(), active: true)
        try await eventually { slot.active?.hasFreshVerifiedStatus == true }
        slot.synchronize(wanted: false)
        #expect(!policy(slot, backend: .eventTap).permitsInput)
        try await eventually { helper.stopRequests > 0 }
        helper.acknowledge()
        try await eventually { !slot.releasePending }
        #expect(policy(slot, backend: .eventTap).permitsInput && slot.retiringCount == 0)
    }
    @Test func hidOffWithUnknownReleaseStaysClosedUntilExplicitRestart() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let slot = slot(helper, liveness, timeout: 0.3)
        slot.synchronize(wanted: true); slot.active?.update(activeConfig(), active: true)
        try await eventually { slot.active?.hasFreshVerifiedStatus == true }
        slot.synchronize(wanted: false)
        helper.dropClients()
        try await eventually { slot.retiringCount == 0 }
        #expect(slot.releaseUnconfirmed && !policy(slot, backend: .eventTap).permitsInput)
        // "恢復／重啟引擎" is the only way back.
        slot.clearUnconfirmedRelease()
        #expect(policy(slot, backend: .eventTap).permitsInput)
    }
    @Test func hidRestartDoesNotConnectANewLeaseWhileTheOldOneIsRetiring() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let slot = slot(helper, liveness)
        slot.synchronize(wanted: true); slot.active?.update(activeConfig(), active: true)
        try await eventually { slot.active?.hasFreshVerifiedStatus == true }
        let configured = helper.configurations
        slot.synchronize(wanted: false); slot.synchronize(wanted: true)
        // BridgeController passes permitsInput, which the pending release blocks.
        var config = activeConfig(generation: 2); config.enabled = policy(slot, backend: .deviceHID).permitsInput
        slot.active?.start(); slot.active?.update(config, active: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!config.enabled && helper.configurations == configured && slot.retiringCount == 1)
        try await eventually { helper.stopRequests > 0 }
        helper.acknowledge()
        try await eventually { !slot.releasePending }
        config.enabled = policy(slot, backend: .deviceHID).permitsInput
        slot.active?.update(config, active: true)
        try await eventually { helper.configurations > configured }
        #expect(config.enabled && helper.configurations > configured && slot.retiringCount == 0)
        slot.stopAll()
    }
    @Test func thousandEnableDisableCyclesRetainNoClientsOrWatches() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness()
        weak var lastClient: HIDBackendClient?
        let slot = HIDBackendSlot(factory: {
            let client = HIDBackendClient(connectionFactory: { NSXPCConnection(listenerEndpoint: helper.listener.endpoint) },
                                          liveness: liveness.value)
            client.configureReplyTimeout = 60; lastClient = client; return client
        })
        for cycle in 0..<1000 {
            slot.synchronize(wanted: true); slot.synchronize(wanted: false)
            if cycle % 50 == 49 { await Task.yield() }   // do not starve other MainActor tests
        }
        #expect(slot.retiringCount == 0 && slot.active == nil && !slot.releasePending)
        #expect(lastClient == nil, "retired clients must be released")
        #expect(liveness.exitHandlers.isEmpty && helper.configurations == 0)
        // Owned leases: each cycle ends with an ACK and leaves nothing behind.
        for generation in 1...20 {
            slot.synchronize(wanted: true); slot.active?.start(); slot.active?.update(activeConfig(generation: UInt64(generation)), active: true)
            try await eventually { slot.active?.hasFreshVerifiedStatus == true }
            slot.synchronize(wanted: false)
            try await eventually { helper.stopRequests > 0 }
            helper.acknowledge()
            try await eventually { slot.retiringCount == 0 }
        }
        #expect(slot.retiringCount == 0 && !slot.releasePending && liveness.cancelled == liveness.exitHandlers.count)
    }
    @Test func timeoutThenExplicitRestartReopensOnlyAfterTheUserAction() async throws {
        let helper = FakeHelper(); defer { helper.shutdown() }
        let liveness = FakeLiveness(); let slot = slot(helper, liveness, timeout: 0.2)
        slot.synchronize(wanted: true); slot.active?.update(activeConfig(), active: true)
        try await eventually { slot.active?.hasFreshVerifiedStatus == true }
        slot.synchronize(wanted: false)
        try await eventually { slot.retiringCount == 0 }
        #expect(slot.releaseUnconfirmed)
        helper.acknowledge()                       // late reply
        try await Task.sleep(for: .milliseconds(100))
        #expect(slot.releaseUnconfirmed && slot.releasePending)
        slot.clearUnconfirmedRelease()
        #expect(!slot.releasePending)
    }
}
