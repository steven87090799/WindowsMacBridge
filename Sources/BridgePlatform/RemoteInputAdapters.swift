import AppKit
import Security
import CryptoKit
import BridgeCore

extension SourceWorkToken {
    /// For queued work only. The input callback reads the atomic gates without a syscall.
    public var validForAsyncWork: Bool {
        guard isCurrent else { return false }
        if producerProcessID == 0 { return producerSession == 0 }
        return producerProcessID > 0 && RemoteProcessResolver.birth(producerProcessID) == producerSession && isCurrent
    }
}

public struct RemoteProcessIdentity: Equatable, Sendable {
    public var pid: Int32
    public var birth: UInt64
    public var path: String
    public var signingID: String
    public var teamID: String
    public var signatureValid: Bool
    public var stableID: String {
        // No PID, typed key or raw serial is persisted. Unsigned producers are path-bound.
        let value = signingID + "|" + teamID + "|" + path
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public init(pid: Int32, birth: UInt64, path: String, signingID: String, teamID: String, signatureValid: Bool) {
        self.pid = pid; self.birth = birth; self.path = path; self.signingID = signingID
        self.teamID = teamID; self.signatureValid = signatureValid
    }
}
public struct RemoteAdapterDescriptor: Sendable {
    public var transport: RemoteTransport = .generic
    public var confidence: InputConfidence = .unknown
    public var independentFlags = false
    public var kind: ProducerKind = .remote
}
public enum RemoteAdapterCatalog {
    public static func classify(_ p: RemoteProcessIdentity) -> RemoteAdapterDescriptor {
        if p.signatureValid && p.signingID == "com.apple.universalcontrol" && p.path.hasPrefix("/System/Library/") {
            return .init(confidence: .known, kind: .universalControl)
        }
        // Chromium's mac input injector sets its OWN modifier flags on each CGEvent.
        // IDs and signing team were checked against the installed Google host, not Chrome.
        let googleHosts = ["com.google.chromeremotedesktop.me2me-host",
                           "com.google.chrome_remote_desktop.remoting_me2me_host",
                           "com.google.chrome.remote_desktop.remote-assistance-host-v2"]
        if p.signatureValid && p.teamID == "EQHXZ8M8AV" && googleHosts.contains(p.signingID) {
            return .init(transport: .googleRemoteDesktop, confidence: .known, independentFlags: true)
        }
        // These IDs identify software, not proof that a viewer is an incoming host.
        // Automatic remains pass-through; actual source PID observation/calibration is required.
        let candidates: [String: RemoteTransport] = [
            "com.microsoft.rdc.macos": .microsoftRemoteDesktop, "com.p5sys.jump.mac.viewer": .jumpDesktop,
            "com.p5sys.jump.mac.viewer.web": .jumpDesktop, "com.anydesk.AnyDesk": .anyDesk,
            "com.teamviewer.TeamViewer": .teamViewer, "tv.parsec.www": .parsec,
            "com.carriez.RustDesk": .rustDesk, "com.nomachine.nxdock": .noMachine,
            "com.realvnc.vncviewer": .vnc]
        if p.signatureValid, let transport = candidates[p.signingID] {
            return .init(transport: transport, confidence: .likely)
        }
        return .init()
    }
    static func discoveryCandidate(_ path: String) -> Bool {
        ["ChromeRemoteDesktopHost.app/", "UniversalControl.app/", "remoting_me2me_host", "AnyDesk.app/",
         "TeamViewer", "RustDesk.app/", "Jump Desktop", "Microsoft Remote Desktop", "Windows App.app/",
         "Parsec.app/", "Splashtop", "NoMachine", "VNC"].contains { path.localizedCaseInsensitiveContains($0) }
    }
}
public enum RemoteProcessResolver {
    public static func birth(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }
    private static func path(_ pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN; that C expression is not imported by Swift.
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
    public static func identity(_ pid: Int32) -> RemoteProcessIdentity? {
        guard let start = birth(pid), let executable = path(pid) else { return nil }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        var identifier = "", team = "", valid = false
        if SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code {
            var information: CFDictionary?
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
               SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
               let values = information as? [String: Any] {
                identifier = values[kSecCodeInfoIdentifier as String] as? String ?? ""
                team = values[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
                valid = SecCodeCheckValidity(code, [], nil) == errSecSuccess
            }
        }
        guard birth(pid) == start else { return nil }
        return .init(pid: pid, birth: start, path: executable, signingID: identifier, teamID: team, signatureValid: valid)
    }
    static func discover() -> [Int32] {
        var values = [Int32](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&values, Int32(values.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        var result = [Int32]()
        for pid in values.prefix(min(Int(bytes), values.count)) where pid > 0 {
            if let executable = path(pid), RemoteAdapterCatalog.discoveryCandidate(executable) {
                result.append(pid); if result.count == 32 { break }
            }
        }
        return result
    }
    /// Explicit CLI diagnostics only. Reads producer metadata; never starts a tap or posts input.
    public static func metadataReport() -> String {
        let rows: [[String: Any]] = discover().compactMap { pid in
            guard let p = identity(pid) else { return nil }
            let a = RemoteAdapterCatalog.classify(p)
            return ["pid": p.pid, "signingID": p.signingID, "teamID": p.teamID, "signatureValid": p.signatureValid,
                    "transport": a.transport.rawValue, "confidence": a.confidence.rawValue, "independentFlags": a.independentFlags,
                    "kind": String(describing: a.kind), "observedIncomingInput": false, "physicallyVerified": false]
        }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true)
        let report: [String: Any] = ["metadataOnly": true, "tapStarted": false, "eventPosted": false, "sources": rows,
                                    "createdTestEventPID": event?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1,
                                    "createdTestEventState": event?.getIntegerValueField(.eventSourceStateID) ?? -999]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
public struct RemoteCalibrationResult: Sendable {
    public let identity: String, processID: Int32, session: UInt64
    public let semantics: RemoteSemantics
}
/// Armed explicitly, records only whether ONE Ctrl+C became Control or Command, never text.
public final class RemoteCalibrationInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var armed: (String, Int32, UInt64)?
    private var result: RemoteCalibrationResult?
    public init() {}
    public func arm(identity: String, processID: Int32, session: UInt64) {
        lock.lock(); armed = (identity, processID, session); result = nil; lock.unlock()
    }
    public func cancel() { lock.lock(); armed = nil; result = nil; lock.unlock() }
    public func observe(processID: Int32, key: UInt16, phase: KeyPhase, flags: Modifiers, repeatKey: Bool) {
        guard phase == .down && key == 8 && !repeatKey, lock.try() else { return }
        defer { lock.unlock() }
        guard let (identity, pid, session) = armed, pid == processID else { return }
        let semantics: RemoteSemantics
        if flags == .control { semantics = .windows }
        else if flags == .command { semantics = .alreadyTranslated }
        else { return }
        result = .init(identity: identity, processID: pid, session: session, semantics: semantics)
        armed = nil
    }
    public func take() -> RemoteCalibrationResult? {
        lock.lock(); defer { lock.unlock() }; let value = result; result = nil; return value
    }
}
public struct RemoteSourceStatus: Equatable, Identifiable, Sendable {
    public var id: String { identity + ".\(processID)" }
    public let identity: String, displayName: String
    public let processID: Int32, session: UInt64
    public let transport: RemoteTransport, confidence: InputConfidence, semantics: RemoteSemantics
    public let observedInput: Bool, learned: Bool
    public var support: InputSupportLevel {
        confidence == .known ? .detected : (semantics == .automatic ? .unknown : .generic)
    }
}
/// Single bounded metadata job. Workspace events and the existing lifecycle tick feed it;
/// no per-key task, subprocess, AX query or process lookup enters the keyboard callback.
@MainActor public final class RemoteSourceRegistry {
    private struct Entry {
        let identity: RemoteProcessIdentity
        let adapter: RemoteAdapterDescriptor
        var producer: RemoteProducer
        var observed = false
    }
    private var entries: [Entry] = []
    private var preferences: [RemoteSourcePreference] = []
    private var pending = [Int32]()
    private var active = false, resolving = false
    private var epoch: UInt64 = 0, revision: UInt64 = 0
    private var hostGeneration: UInt64 = 0
    private var discoveryRequested = false
    public private(set) var snapshot = InputRoutingSnapshot()
    public private(set) var statuses: [RemoteSourceStatus] = []
    public var onChange: (() -> Void)?
    public init() {}
    public func configure(active: Bool, preferences: [RemoteSourcePreference], generation: UInt64 = 0) {
        if hostGeneration != generation {
            epoch &+= 1; hostGeneration = generation
            if active { discoveryRequested = true }
        }
        if self.active != active {
            epoch &+= 1; self.active = active
            for entry in entries { entry.producer.work.invalidate() }
            entries.removeAll(); pending.removeAll(); snapshot = .init(); statuses = []
            discoveryRequested = active; onChange?()
            if active { maintain([]) }
        }
        guard self.preferences != preferences else { return }
        self.preferences = Array(preferences.prefix(32)); revision &+= 1
        for i in entries.indices {
            let pref = self.preferences.first { $0.identity == entries[i].identity.stableID }
            let semantics = pref?.semantics ?? .automatic
            let transport = pref?.transport == .generic ? entries[i].adapter.transport : (pref?.transport ?? entries[i].adapter.transport)
            if entries[i].producer.semantics != semantics || entries[i].producer.transport != transport {
                entries[i].producer.work.invalidate()
                entries[i].producer = producer(entries[i].identity, adapter: entries[i].adapter)
            }
        }
        publish()
    }
    public func discover() { guard active else { return }; discoveryRequested = true; maintain([]) }
    public func maintain(_ observedPIDs: [Int32]) {
        guard active else { return }
        var changed = false
        for i in entries.indices.reversed() where RemoteProcessResolver.birth(entries[i].identity.pid) != entries[i].identity.birth {
            entries[i].producer.work.invalidate(); entries.remove(at: i); changed = true
        }
        for pid in observedPIDs.prefix(16) where pid != ProcessInfo.processInfo.processIdentifier {
            if let i = entries.firstIndex(where: { $0.identity.pid == pid }) {
                if !entries[i].observed { entries[i].observed = true; changed = true }
            } else if pending.count < 16 && !pending.contains(pid) { pending.append(pid) }
        }
        if changed { publish() }
        guard !resolving, !pending.isEmpty || discoveryRequested else { return }
        let requested = pending; pending.removeAll(); let discover = discoveryRequested; discoveryRequested = false
        let jobEpoch = epoch; resolving = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                var ids = [Int32]()
                for pid in (discover ? RemoteProcessResolver.discover() : []) + requested where !ids.contains(pid) {
                    ids.append(pid); if ids.count == 32 { break }
                }
                return ids.compactMap { RemoteProcessResolver.identity($0) }
            }.value
            guard let self else { return }; self.resolving = false
            guard self.active && self.epoch == jobEpoch else { self.maintain([]); return }
            for identity in result where RemoteProcessResolver.birth(identity.pid) == identity.birth {
                guard !self.entries.contains(where: { $0.identity.pid == identity.pid }), self.entries.count < 32 else { continue }
                let adapter = RemoteAdapterCatalog.classify(identity)
                self.entries.append(.init(identity: identity, adapter: adapter,
                                          producer: self.producer(identity, adapter: adapter), observed: requested.contains(identity.pid)))
            }
            self.publish(); self.maintain([])
        }
    }
    private func producer(_ identity: RemoteProcessIdentity, adapter: RemoteAdapterDescriptor) -> RemoteProducer {
        let pref = preferences.first { $0.identity == identity.stableID }
        return .init(processID: identity.pid, identity: identity.stableID, session: identity.birth, revision: revision,
                     transport: pref?.transport == .generic ? adapter.transport : (pref?.transport ?? adapter.transport),
                     confidence: adapter.confidence, semantics: pref?.semantics ?? .automatic,
                     independentFlags: adapter.independentFlags, kind: adapter.kind)
    }
    private func publish() {
        snapshot = .init(producers: entries.map(\.producer))
        statuses = entries.filter { $0.adapter.kind == .remote }.map { e in
            .init(identity: e.identity.stableID, displayName: e.identity.signingID.isEmpty ? URL(fileURLWithPath: e.identity.path).lastPathComponent : e.identity.signingID,
                  processID: e.identity.pid, session: e.identity.birth, transport: e.producer.transport,
                  confidence: e.adapter.confidence, semantics: e.producer.semantics, observedInput: e.observed,
                  learned: preferences.first { $0.identity == e.identity.stableID }?.learned ?? false)
        }
        onChange?()
    }
}
