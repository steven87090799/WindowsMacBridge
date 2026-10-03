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
        capture.onStatus = { [weak self] status, generation in
            guard let peer = self?.connection,
                  let remote = peer.remoteObjectProxy as? HIDControllerProtocol,
                  let data = try? JSONEncoder().encode(status), data.count <= 16384 else { return }
            remote.receiveStatus(data, generation: generation)
        }
        captureStorage = capture
        return capture
    }
    private let pinnedHash: Data
    /// Enforced by XPC for every message, not only when the connection is accepted.
    private let clientRequirement: String
    private var connection: NSXPCConnection?
    private let acceptedConnections = ConnectionRetainer<NSXPCConnection>()
    /// Owners replaced by a newer configure. A request already queued from a
    /// displaced owner must not take the lease back (main queue only, bounded
    /// by acceptedConnections).
    private var displaced = Set<ObjectIdentifier>()
    private let listener = NSXPCListener(machServiceName: HIDService.name)
    private var termination: DispatchSourceSignal?
    private var idleExit: DispatchWorkItem?
    /// The pin is read from the same descriptor that was validated: no symlink,
    /// root-owned, regular, not group/world-writable, bounded.
    static func readPin(_ path: String) -> Data? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o022 == 0, info.st_nlink == 1, info.st_size > 0, info.st_size < 4096,
              let data = try? file.read(upToCount: 4096), data.count < 4096 else { return nil }
        return data
    }
    init?(pinPath: String = HIDService.root + "/controller.plist") {
        guard geteuid() == 0,
              let data = Self.readPin(pinPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let hash = plist["CDHash"] as? Data, hash.count == 20,
              let requirement = ControllerCodeRequirement.make(identifier: "local.WindowsMacBridge", cdhash: hash) else { return nil }
        self.pinnedHash = hash
        self.clientRequirement = requirement
        super.init(); listener.delegate = self
    }
    func run() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        // stop() closes seized devices synchronously. _exit avoids running C++
        // static destructors while the VirtualHID teardown worker may be active.
        source.setEventHandler { [weak self] in self?.captureStorage?.stop(); _exit(0) }
        source.resume(); termination = source
        guard let lifetime = PassiveRunLoopLifetime() else { exit(70) }
        withExtendedLifetime((self, lifetime)) {
            listener.resume()
            // A launch by a lookup that is then rejected must not leave a resident root process.
            scheduleIdleExit()
            RunLoop.main.run()
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection candidate: NSXPCConnection) -> Bool {
        guard authenticated(candidate), acceptedConnections.insert(candidate) else {
            DispatchQueue.main.async { [weak self] in self?.scheduleIdleExit() }
            return false
        }
        DispatchQueue.main.async { [weak self] in self?.idleExit?.cancel(); self?.idleExit = nil }
        let api = Endpoint(service: self, connection: candidate)
        candidate.exportedInterface = NSXPCInterface(with: HIDHelperProtocol.self)
        candidate.exportedObject = api
        candidate.remoteObjectInterface = NSXPCInterface(with: HIDControllerProtocol.self)
        candidate.invalidationHandler = { [weak self, weak candidate] in
            DispatchQueue.main.async {
                guard let self, let candidate else { return }
                self.acceptedConnections.remove(candidate)
                self.displaced.remove(ObjectIdentifier(candidate))
                if self.connection === candidate {
                    self.captureStorage?.stop(); self.connection = nil
                }
                self.scheduleIdleExit()
            }
        }
        candidate.interruptionHandler = candidate.invalidationHandler
        // The accept-time check above resolves the peer by PID. Bind every later
        // message to the pinned code via the sender's audit token as well.
        candidate.setCodeSigningRequirement(clientRequirement)
        // Permission-only connections never take keyboard ownership. The
        // authenticated configure request acquires the single capture lease.
        candidate.resume(); return true
    }
    private func scheduleIdleExit() {
        idleExit?.cancel()
        guard acceptedConnections.isEmpty, connection == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.acceptedConnections.isEmpty, self.connection == nil else { return }
            // Teardown can finish after a new controller connected; only exit if still idle.
            if let capture = self.captureStorage {
                capture.stop { [weak self] in
                    guard let self, self.acceptedConnections.isEmpty, self.connection == nil else { return }
                    exit(0)
                }
            } else { exit(0) }
        }
        idleExit = work; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
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
                      !service.displaced.contains(ObjectIdentifier(connection)),
                      connection.effectiveUserIdentifier == DeviceCapture.consoleUID() else { reply(Data()); return }
                if service.connection !== connection {
                    if let previous = service.connection { service.displaced.insert(ObjectIdentifier(previous)) }
                    service.capture.stop(); service.connection?.invalidate(); service.connection = connection
                }
                service.capture.configure(config, uid: connection.effectiveUserIdentifier)
                reply((try? JSONEncoder().encode(service.capture.status)) ?? Data())
            }
        }
        func stop(withReply reply: @escaping () -> Void) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let service, service.connection === connection else { reply(); return }
                service.capture.stop(completion: reply)
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
