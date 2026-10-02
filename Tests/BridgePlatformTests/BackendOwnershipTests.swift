import Foundation
import Testing
import BridgeCore
import HIDProtocol
@testable import BridgePlatform

private final class OfflineHelper: NSObject, HIDHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var reply: (() -> Void)?
    private var configureCount = 0
    var configurations: Int { lock.lock(); defer { lock.unlock() }; return configureCount }
    var hasStop: Bool { lock.lock(); defer { lock.unlock() }; return reply != nil }
    func acknowledge() { lock.lock(); let action = reply; reply = nil; lock.unlock(); action?() }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HIDHelperProtocol.self)
        connection.exportedObject = self; connection.resume(); return true
    }
    func configure(_ data: Data, withReply reply: @escaping (Data) -> Void) {
        lock.lock(); configureCount += 1; lock.unlock()
        reply((try? JSONEncoder().encode(HIDStatus())) ?? Data())
    }
    func stop(withReply reply: @escaping () -> Void) { lock.lock(); self.reply = reply; lock.unlock() }
    func requestInputAccess(withReply reply: @escaping (Bool) -> Void) { reply(false) }
    func checkInputAccess(withReply reply: @escaping (Bool) -> Void) { reply(false) }
}

@MainActor struct BackendOwnershipTests {
    @Test func permissionProbeTransportFailureReturnsUnknownWithoutCapturing() async {
        let client = HIDBackendClient(connectionFactory: {
            NSXPCConnection(machServiceName: "local.WindowsMacBridge.MissingFixture.\(UUID().uuidString)")
        })
        defer { client.stop() }
        let grant: Bool? = await withCheckedContinuation { continuation in
            client.checkInputAccess { continuation.resume(returning: $0) }
        }
        #expect(grant == nil)
        #expect(!client.hasOwnership && !client.releasePending)
    }
    @Test func permissionSetupWorksBeforeBackendActivationWithoutCapturingAKeyboard() async {
        let helper = OfflineHelper()
        let listener = NSXPCListener.anonymous(); listener.delegate = helper; listener.resume()
        defer { listener.invalidate() }
        let client = HIDBackendClient(connectionFactory: { NSXPCConnection(listenerEndpoint: listener.endpoint) })
        let grant: Bool? = await withCheckedContinuation { continuation in
            client.checkInputAccess { continuation.resume(returning: $0) }
        }
        #expect(grant == false)
        #expect(helper.configurations == 0 && !client.hasOwnership && !client.releasePending)
    }
    @Test func pendingStopConnectionDoesNotRetainItsController() async throws {
        let helper = OfflineHelper()
        let listener = NSXPCListener.anonymous(); listener.delegate = helper; listener.resume()
        defer { helper.acknowledge(); listener.invalidate() }
        var client: HIDBackendClient? = HIDBackendClient(connectionFactory: {
            NSXPCConnection(listenerEndpoint: listener.endpoint)
        }, stopAcknowledgementTimeout: 0.01)
        weak var released = client
        var config = EngineConfiguration(); config.enabled = true; config.generation = 1
        config.context = .init(processID: .max, bundleID: "test", mode: .macOS)
        client?.start(); client?.update(config, active: true)
        for _ in 0..<20 { await Task.yield() }
        client?.stop()
        for _ in 0..<100 where !helper.hasStop { try await Task.sleep(for: .milliseconds(2)) }
        #expect(helper.hasStop)
        client = nil
        for _ in 0..<100 where released != nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(released == nil)
    }
    @Test func realIPCTransportWaitsForStopReplyAndTimeoutNeverClaimsRelease() async throws {
        let helper = OfflineHelper()
        let listener = NSXPCListener.anonymous(); listener.delegate = helper; listener.resume()
        defer { listener.invalidate() }
        let client = HIDBackendClient(connectionFactory: { NSXPCConnection(listenerEndpoint: listener.endpoint) }, stopAcknowledgementTimeout: 0.01)
        var config = EngineConfiguration(); config.enabled = true; config.generation = 1
        config.context = .init(processID: .max, bundleID: "test", mode: .macOS)
        client.start(); client.update(config, active: true)
        for _ in 0..<20 { await Task.yield() }
        client.releaseOwnership()
        for _ in 0..<100 where !helper.hasStop { try await Task.sleep(for: .milliseconds(2)) }
        #expect(helper.hasStop && client.releasePending)
        try await Task.sleep(for: .milliseconds(30))
        #expect(client.releasePending && client.hasOwnership)
        helper.acknowledge()
        for _ in 0..<100 where client.releasePending { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!client.releasePending && !client.hasOwnership)
        client.stop()
    }
    @Test func helperActionCannotUseCurrentOrOldEpochAsDestinationDeliveryEvidence() async throws {
        let helper = OfflineHelper()
        let listener = NSXPCListener.anonymous(); listener.delegate = helper; listener.resume()
        defer { helper.acknowledge(); listener.invalidate() }
        let client = HIDBackendClient(connectionFactory: { NSXPCConnection(listenerEndpoint: listener.endpoint) })
        var config = EngineConfiguration(); config.enabled = true; config.layoutSupported = true; config.generation = 10
        config.context = .init(processID: .max, bundleID: "test", mode: .macOS)
        var captures = 0; client.onScreenshot = { _ in captures += 1 }
        client.update(config, active: true)
        client.performAction("screenshot.region", processID: .max, generation: 1)
        for _ in 0..<10 { await Task.yield() }; #expect(captures == 0)
        config.deviceInputs = [.init(identity: "a", experience: .nativeMac)]
        client.update(config, active: true)
        client.performAction("screenshot.region", processID: .max, generation: 1)
        for _ in 0..<10 { await Task.yield() }; #expect(captures == 0)
        client.performAction("screenshot.region", processID: .max, generation: 2)
        for _ in 0..<10 { await Task.yield() }; #expect(captures == 0 && config.generation == 10)
        client.stop()
    }
}
