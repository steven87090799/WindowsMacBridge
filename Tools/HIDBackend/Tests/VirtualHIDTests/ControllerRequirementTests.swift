import Foundation
import Security
import Testing
import HIDLifecycle

@objc private protocol RequirementPing {
    func ping(withReply reply: @escaping (Bool) -> Void)
}
private final class RequirementPingService: NSObject, RequirementPing, NSXPCListenerDelegate, @unchecked Sendable {
    private let requirement: String
    init(requirement: String) { self.requirement = requirement }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RequirementPing.self)
        connection.exportedObject = self
        connection.setCodeSigningRequirement(requirement)
        connection.resume(); return true
    }
    func ping(withReply reply: @escaping (Bool) -> Void) { reply(true) }
}

struct ControllerRequirementTests {
    private static func ownSigning() -> (identifier: String, cdhash: Data)? {
        var running: SecCode?, code: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let identifier = values[kSecCodeInfoIdentifier as String] as? String,
              let hash = values[kSecCodeInfoUnique as String] as? Data else { return nil }
        return (identifier, hash)
    }
    private static func ping(_ requirement: String) async -> Bool {
        let service = RequirementPingService(requirement: requirement)
        let listener = NSXPCListener.anonymous(); listener.delegate = service; listener.resume()
        defer { listener.invalidate() }
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: RequirementPing.self)
        connection.resume(); defer { connection.invalidate() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = OnceFlag()
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                if once.claim() { continuation.resume(returning: false) }
            } as? RequirementPing
            proxy?.ping { value in if once.claim() { continuation.resume(returning: value) } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if once.claim() { continuation.resume(returning: false) }
            }
        }
    }
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock(); private var used = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }

    @Test func requirementTextIsBoundedAndValidated() {
        let hash = Data(repeating: 0xab, count: 20)
        #expect(ControllerCodeRequirement.make(identifier: "local.WindowsMacBridge", cdhash: hash) ==
                "identifier \"local.WindowsMacBridge\" and cdhash H\"" + String(repeating: "ab", count: 20) + "\"")
        #expect(ControllerCodeRequirement.make(identifier: "local.WindowsMacBridge", cdhash: Data(count: 19)) == nil)
        #expect(ControllerCodeRequirement.make(identifier: "", cdhash: hash) == nil)
        #expect(ControllerCodeRequirement.make(identifier: "x\" or anchor apple", cdhash: hash) == nil)
    }

    @Test func pinnedRequirementAcceptsTheMatchingPeerAndRejectsAnyOtherCode() async {
        // arm64 hosts are always at least ad-hoc signed, so this cannot skip silently.
        let own = Self.ownSigning()
        #expect(own != nil)
        guard let own, let matching = ControllerCodeRequirement.make(identifier: own.identifier, cdhash: own.cdhash) else {
            Issue.record("test host signing identity unusable for a requirement"); return
        }
        #expect(await Self.ping(matching))
        var other = own.cdhash; other[0] ^= 0xff
        let mismatched = ControllerCodeRequirement.make(identifier: own.identifier, cdhash: other)!
        #expect(await !Self.ping(mismatched))
    }
}
