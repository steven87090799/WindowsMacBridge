import Foundation
import BridgeCore

public struct RemoteCalibrationStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, waiting, review, saved, cancelled }
    public var phase: Phase = .idle
    public var targetIdentity: String?
    public var targetName: String?
    public var deadline: Double?
    public var candidate: RemoteSemantics?
    public var notice: String?
    public var canUndo = false
    public var isActive: Bool { phase == .waiting || phase == .review }
    public init() {}
}

public struct RemoteCalibrationUndo: Sendable {
    public let identity: String
    public let previous: RemoteSourcePreference?
    public let applied: RemoteSourcePreference
}

/// Main-actor coordination, driven only by explicit actions, one result and one
/// deadline. The input callback records one chord and never resolves processes.
@MainActor public final class RemoteCalibrationCoordinator {
    private let inbox: RemoteCalibrationInbox
    private let uptime: () -> Double
    private let birth: (Int32) -> UInt64?
    private var target: RemoteProducer?
    private var requestID: UInt64?
    private var policyAnchor: RuntimePolicyInput?
    private var previous: RemoteSourcePreference?
    private var undo: RemoteCalibrationUndo?
    public private(set) var status = RemoteCalibrationStatus()

    public init(inbox: RemoteCalibrationInbox,
                uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
                birth: @escaping (Int32) -> UInt64? = RemoteProcessResolver.birth) {
        self.inbox = inbox; self.uptime = uptime; self.birth = birth
    }

    @discardableResult public func begin(source: RemoteSourceStatus, policy: RuntimePolicySnapshot,
        producers: [RemoteProducer], previous: RemoteSourcePreference?) -> Bool {
        cancel()
        guard source.observedInput, Self.allowsCalibration(policy),
              let producer = producers.first(where: {
                  $0.identity == source.identity && $0.processID == source.processID && $0.session == source.session && $0.kind == .remote
              }), producer.work.isCurrent, birth(source.processID) == source.session else {
            status.notice = "請先從此來源送入按鍵，並啟用 Windows 模式及必要權限後再校準。"
            return false
        }
        self.previous = previous; target = producer
        policyAnchor = Self.normalized(policy.input)
        requestID = inbox.arm(identity: source.identity, processID: source.processID, session: source.session, validity: producer.work)
        status.phase = .waiting; status.targetIdentity = source.identity; status.targetName = source.displayName
        status.deadline = uptime() + 60; status.candidate = nil
        status.canUndo = false
        status.notice = "請在這台 Mac 的文字 App 選取測試文字，再從指定遠端電腦按一次 Ctrl+C；60 秒內有效。"
        return true
    }

    public func refresh(policy: RuntimePolicySnapshot, producers: [RemoteProducer]) {
        guard status.isActive else { return }
        guard let target, target.work.isCurrent, producers.contains(target), birth(target.processID) == target.session else {
            cancel(notice: "來源已離線或重新啟動；校準已取消，原設定保留。")
            return
        }
        guard Self.allowsCalibration(policy), Self.normalized(policy.input) == policyAnchor else {
            cancel(notice: "輸入政策已改變；校準已取消，原設定保留。")
            return
        }
        guard let deadline = status.deadline, uptime() < deadline else {
            cancel(notice: "校準逾時；原設定保留。")
            return
        }
        guard status.phase == .waiting, let result = inbox.take(), result.requestID == requestID,
              result.identity == target.identity, result.processID == target.processID,
              result.session == target.session else { return }
        status.phase = .review; status.candidate = result.semantics
        status.notice = "已辨識：\(result.semantics.title)。請確認後套用；確認前設定不變。"
    }

    public func proposedPreference(policy: RuntimePolicySnapshot, producers: [RemoteProducer]) -> RemoteSourcePreference? {
        refresh(policy: policy, producers: producers)
        guard status.phase == .review, let target, let candidate = status.candidate else { return nil }
        return .init(identity: target.identity, semantics: candidate, transport: target.transport, learned: true)
    }

    public func didSave(_ preference: RemoteSourcePreference, success: Bool) {
        guard status.phase == .review, preference.identity == target?.identity,
              preference.semantics == status.candidate else { return }
        guard success else { status.notice = "來源設定儲存失敗；尚未套用，可重試或取消。"; return }
        undo = .init(identity: preference.identity, previous: previous, applied: preference)
        inbox.cancel(); target = nil; requestID = nil; policyAnchor = nil; previous = nil
        status.phase = .saved; status.deadline = nil; status.candidate = nil; status.canUndo = true
        status.notice = "已保存校準結果；可還原校準前設定。"
    }

    public func cancel(notice: String? = nil) {
        inbox.cancel(); target = nil; requestID = nil; policyAnchor = nil; previous = nil
        status.phase = notice == nil ? .idle : .cancelled
        status.targetIdentity = nil; status.targetName = nil; status.deadline = nil; status.candidate = nil
        status.notice = notice; status.canUndo = undo != nil
    }

    public func undoProposal(current: [RemoteSourcePreference]) -> RemoteCalibrationUndo? {
        guard !status.isActive else { return nil }
        guard let undo, current.first(where: { $0.identity == undo.identity }) == undo.applied else {
            self.undo = nil; status.canUndo = false
            status.notice = "來源設定已另行修改；保留目前設定。"
            return nil
        }
        return undo
    }
    public func didUndo(success: Bool) {
        guard success else { status.notice = "還原儲存失敗，原設定保留。"; return }
        undo = nil; status.canUndo = false
        cancel(notice: "已還原校準前的來源設定。")
    }

    private static func normalized(_ input: RuntimePolicyInput) -> RuntimePolicyInput {
        var value = input; value.foreground = ApplicationContext(); return value
    }
    private static func allowsCalibration(_ policy: RuntimePolicySnapshot) -> Bool {
        policy.permitsShortcuts && (policy.input.foreground.mode.allowsTranslation ||
            policy.input.foreground.bundleID == "local.WindowsMacBridge")
    }
}
