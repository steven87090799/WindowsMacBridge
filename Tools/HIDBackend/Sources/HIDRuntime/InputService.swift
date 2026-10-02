import Foundation
import Security
import IOKit.hid
import HIDProtocol
import HIDLifecycle

/// Installed root-owned pin + console UID authenticate the single controller.
/// No commands, paths, arbitrary output reports or clipboard data are accepted over IPC.
final class InputService: NSObject, NSXPCListenerDelegate {
    private var captureStorage: DeviceCapture?
    private var capture: DeviceCapture {
        if let captureStorage { return captureStorage }
        let capture = DeviceCapture()
        capture.onAction = { [weak self] action, pid, generation in
            guard let remote = self?.connection?.remoteObjectProxy as? HIDControllerProtocol else { return }
            remote.performAction(HIDActionCodec.encode(action), processID: pid, generation: generation)
        }
        captureStorage = capture
        return capture
    }
    private let pinnedHash: Data
    private var connection: NSXPCConnection?
    private let listener = NSXPCListener(machServiceName: HIDService.name)
    private var termination: DispatchSourceSignal?
    init?(pinPath: String = HIDService.root + "/controller.plist") {
        guard geteuid() == 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: pinPath),
              (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
              ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0,
              attrs[.type] as? FileAttributeType == .typeRegular,
              let data = try? Data(contentsOf: URL(fileURLWithPath: pinPath)), data.count < 4096,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let hash = plist["CDHash"] as? Data, hash.count == 20 else { return nil }
        self.pinnedHash = hash
        super.init(); listener.delegate = self
    }
    func run() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in self?.captureStorage?.stop(); exit(0) }
        source.resume(); termination = source
        guard let lifetime = PassiveRunLoopLifetime() else { exit(70) }
        withExtendedLifetime(lifetime) { listener.resume(); RunLoop.main.run() }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection candidate: NSXPCConnection) -> Bool {
        guard authenticated(candidate) else { return false }
        let api = Endpoint(service: self, connection: candidate)
        candidate.exportedInterface = NSXPCInterface(with: HIDHelperProtocol.self)
        candidate.exportedObject = api
        candidate.remoteObjectInterface = NSXPCInterface(with: HIDControllerProtocol.self)
        candidate.invalidationHandler = { [weak self, weak candidate] in
            DispatchQueue.main.async {
                if self?.connection === candidate {
                    self?.captureStorage?.stop(); self?.connection = nil; exit(0)
                }
                // A permission-only probe has no capture lease. Exit after its
                // reply/connection ends so the next check uses a fresh TCC client.
                if self?.connection == nil && self?.captureStorage == nil { exit(0) }
            }
        }
        candidate.interruptionHandler = candidate.invalidationHandler
        // Permission-only connections never take keyboard ownership. The
        // authenticated configure request acquires the single capture lease.
        candidate.resume(); return true
    }
    private func authenticated(_ connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0,
              connection.effectiveUserIdentifier == DeviceCapture.consoleUID() else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return false }
        var info: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], values[kSecCodeInfoUnique as String] as? Data == pinnedHash,
              values[kSecCodeInfoIdentifier as String] as? String == "local.WindowsMacBridge" else { return false }
        return true
    }
    private final class Endpoint: NSObject, HIDHelperProtocol {
        weak var service: InputService?
        weak var connection: NSXPCConnection?
        init(service: InputService, connection: NSXPCConnection) { self.service = service; self.connection = connection }
        func configure(_ data: Data, withReply reply: @escaping (Data) -> Void) {
            guard data.count <= 8192, let config = try? JSONDecoder().decode(HIDConfiguration.self, from: data), config.valid else {
                connection?.invalidate(); reply(Data()); return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, let service, let connection,
                      connection.effectiveUserIdentifier == DeviceCapture.consoleUID() else { reply(Data()); return }
                if service.connection !== connection {
                    service.capture.stop(); service.connection?.invalidate(); service.connection = connection
                }
                service.capture.configure(config, uid: connection.effectiveUserIdentifier)
                reply((try? JSONEncoder().encode(service.capture.status)) ?? Data())
            }
        }
        func stop(withReply reply: @escaping () -> Void) {
            DispatchQueue.main.async { [weak self] in
                if let self, let service, service.connection === connection { service.capture.stop() }
                reply()
            }
        }
        func requestInputAccess(withReply reply: @escaping (Bool) -> Void) {
            DispatchQueue.main.async { [weak self] in
                guard let self, service != nil, let connection,
                      connection.effectiveUserIdentifier == DeviceCapture.consoleUID() else { reply(false); return }
                // Root daemons cannot present a login-session permission UI.
                // The main App requests its own permission in the login session.
                reply(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
            }
        }
        func checkInputAccess(withReply reply: @escaping (Bool) -> Void) {
            DispatchQueue.main.async { [weak self] in
                guard let self, service != nil, let connection,
                      connection.effectiveUserIdentifier == DeviceCapture.consoleUID() else { reply(false); return }
                reply(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
            }
        }
    }
}
