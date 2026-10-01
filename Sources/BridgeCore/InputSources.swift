import Foundation
import BridgeWorkGate

public enum RemoteSemantics: String, Codable, CaseIterable, Sendable {
    case automatic, windows, macOS, alreadyTranslated
    public var title: String {
        switch self {
        case .automatic: "自動（未知來源保留原樣）"
        case .windows: "原始 Windows 按鍵"
        case .macOS: "原生 Mac 按鍵"
        case .alreadyTranslated: "已轉成 Mac 快捷鍵"
        }
    }
}
public enum RemoteTransport: String, Codable, CaseIterable, Sendable {
    case googleRemoteDesktop, microsoftRemoteDesktop, jumpDesktop, anyDesk, teamViewer
    case parsec, rustDesk, splashtop, noMachine, vnc, generic
    public var title: String {
        switch self {
        case .googleRemoteDesktop: "Chrome Remote Desktop"
        case .microsoftRemoteDesktop: "Windows App / Microsoft Remote Desktop"
        case .jumpDesktop: "Jump Desktop"
        case .anyDesk: "AnyDesk"
        case .teamViewer: "TeamViewer"
        case .parsec: "Parsec"
        case .rustDesk: "RustDesk"
        case .splashtop: "Splashtop"
        case .noMachine: "NoMachine"
        case .vnc: "VNC"
        case .generic: "其他合成輸入"
        }
    }
}
public enum InputConfidence: String, Codable, Sendable { case known, likely, unknown }
public enum InputSupportLevel: String, Sendable { case verified, detected, generic, unknown }
public enum DeviceExperience: String, Codable, CaseIterable, Sendable { case windows, nativeMac }
public struct RemoteSourcePreference: Codable, Equatable, Sendable {
    public var identity: String
    public var semantics: RemoteSemantics
    public var transport: RemoteTransport
    public var learned: Bool
    public init(identity: String, semantics: RemoteSemantics = .automatic, transport: RemoteTransport = .generic, learned: Bool = false) {
        self.identity = identity; self.semantics = semantics; self.transport = transport; self.learned = learned
    }
}
public struct DeviceInputPreference: Codable, Equatable, Sendable {
    public var identity: String
    public var experience: DeviceExperience
    public init(identity: String, experience: DeviceExperience) { self.identity = identity; self.experience = experience }
}
/// Revoked before a source/policy replacement is published. Does not retain an engine or task.
public final class SourceWorkGate: @unchecked Sendable {
    // C11 atomic_bool works on macOS 14 as well. Swift Synchronization.Atomic requires
    // newer OS versions. ARC keeps the allocation alive for every in-flight token.
    private let storage: OpaquePointer
    public init() {
        guard let storage = WMBWorkGateCreate() else { preconditionFailure("Unable to allocate source work gate") }
        self.storage = storage
    }
    deinit { WMBWorkGateDestroy(storage) }
    public var isCurrent: Bool { WMBWorkGateIsCurrent(storage) }
    public var isCurrentWithoutWaiting: Bool { isCurrent }
    public func invalidate() { WMBWorkGateInvalidate(storage) }
}
public struct SourceWorkToken: Sendable {
    private let origin: SourceWorkGate
    private let frame: SourceWorkGate
    public let producerProcessID: Int32
    public let producerSession: UInt64
    public init(origin: SourceWorkGate, frame: SourceWorkGate, producerProcessID: Int32 = 0, producerSession: UInt64 = 0) {
        self.origin = origin; self.frame = frame
        self.producerProcessID = producerProcessID; self.producerSession = producerSession
    }
    public var isCurrent: Bool { origin.isCurrent && frame.isCurrent }
}
public enum ProducerKind: Sendable { case remote, universalControl, bridge, virtual }
public struct RemoteProducer: Equatable, Sendable {
    public var processID: Int32
    public var identity: String
    public var session: UInt64
    public var revision: UInt64
    public var transport: RemoteTransport
    public var confidence: InputConfidence
    public var semantics: RemoteSemantics
    public var independentFlags: Bool
    public var kind: ProducerKind
    public let work: SourceWorkGate
    public init(processID: Int32, identity: String, session: UInt64, revision: UInt64,
                transport: RemoteTransport, confidence: InputConfidence, semantics: RemoteSemantics = .automatic,
                independentFlags: Bool = false, kind: ProducerKind = .remote, work: SourceWorkGate = .init()) {
        self.processID = processID; self.identity = identity; self.session = session; self.revision = revision
        self.transport = transport; self.confidence = confidence; self.semantics = semantics
        self.independentFlags = independentFlags; self.kind = kind; self.work = work
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.processID == b.processID && a.identity == b.identity && a.session == b.session && a.revision == b.revision &&
        a.transport == b.transport && a.confidence == b.confidence && a.semantics == b.semantics &&
        a.independentFlags == b.independentFlags && a.kind == b.kind && a.work === b.work
    }
}
public struct InputOriginEvidence: Sendable {
    public var processID: Int32
    public var stateID: Int64
    public var ownEvent: Bool
    public init(processID: Int32, stateID: Int64, ownEvent: Bool = false) {
        self.processID = processID; self.stateID = stateID; self.ownEvent = ownEvent
    }
}
public enum InputSourceClass: Equatable, Sendable {
    case physicalFallback, universalControl, bridgeOutput, virtualPassThrough, remote(Int), unknown
}
public struct InputRoutingSnapshot: Equatable, Sendable {
    public let producers: [RemoteProducer]
    public init(producers: [RemoteProducer] = []) {
        var values = [RemoteProducer](); values.reserveCapacity(32)
        for p in producers.prefix(32) where p.processID > 0 && !values.contains(where: { $0.processID == p.processID }) { values.append(p) }
        self.producers = values
    }
    public func classify(_ evidence: InputOriginEvidence, physicalBackend: InputBackend) -> InputSourceClass {
        if evidence.ownEvent { return .bridgeOutput }
        if let index = producers.firstIndex(where: { $0.processID == evidence.processID }) {
            switch producers[index].kind {
            case .remote: return .remote(index)
            case .universalControl: return .universalControl
            case .bridge: return .bridgeOutput
            case .virtual: return .virtualPassThrough
            }
        }
        // Aggregate source state alone is NOT proof of a remote or physical origin.
        if evidence.processID == 0 && evidence.stateID == 1 {
            return physicalBackend == .eventTap ? .physicalFallback : .virtualPassThrough
        }
        return .unknown
    }
}
/// A callback can submit only bounded metadata. Resolving a PID is never callback work.
public final class InputProducerInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var slots = [Int32](repeating: 0, count: 16)
    public init() {}
    public func observe(_ pid: Int32) {
        guard pid > 0, lock.try() else { return }; defer { lock.unlock() }
        guard !slots.contains(pid), let index = slots.firstIndex(of: 0) else { return }
        slots[index] = pid
    }
    public func take() -> [Int32] {
        lock.lock(); defer { lock.unlock() }
        let result = slots.filter { $0 > 0 }
        for i in slots.indices { slots[i] = 0 }; return result
    }
}
public struct SourceTranslationConfiguration: Equatable, Sendable {
    public var context = ApplicationContext()
    public var enabled = false, layoutSupported = false, finderEnabled = false, finderPermanentDeleteEnabled = false
    public var textNavigationEnabled = true, altF4Enabled = false, screenshotEnabled = false
    public var winRunEnabled = false, winSettingsEnabled = false, winTaskViewEnabled = false
    public var printScreen: PrintScreenBehavior = .snipping
    public var generation: UInt64 = 0
    public init() {}
}
public struct RoutedInputDecision: Sendable {
    public var decision: EventDecision
    public var validity: SourceWorkToken?
    public init(_ decision: EventDecision = .passThrough, validity: SourceWorkToken? = nil) {
        self.decision = decision; self.validity = validity
    }
}
