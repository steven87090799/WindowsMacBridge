import Foundation
import BridgeCore

public struct MacBookKeyboardService: Sendable {
    public var identity: MacBookKeyboardIdentity
    /// nil means malformed/unsupported, rather than an empty mapping.
    public var userMapping: [NativeKeyMapping]?
    public var modifierMapping: [NativeKeyMapping]?
    public init(identity: MacBookKeyboardIdentity, userMapping: [NativeKeyMapping]?,
                modifierMapping: [NativeKeyMapping]? = []) {
        self.identity = identity; self.userMapping = userMapping; self.modifierMapping = modifierMapping
    }
}

@MainActor public protocol MacBookKeyboardMappingBackend: AnyObject {
    var portable: Bool { get }
    var bootID: String { get }
    var keysNeutral: Bool { get }
    func services() -> [MacBookKeyboardService]?
    func write(_ mapping: [NativeKeyMapping], serviceID: UInt64) -> Bool
    func observeChanges(_ action: @escaping @MainActor () -> Void) -> Bool
    func stopObserving()
}

public struct MacBookKeyboardMappingStatus: Equatable, Sendable {
    public var activeDevices = 0
    public var summary = "已關閉"
    public var issue: String?
    public var restorePending = false
    public var awaitingNeutral = false
    public init() {}
}

/// Native service properties, outside Event Tap callbacks. No key capture or periodic timer.
@MainActor public final class MacBookKeyboardMapper {
    private struct Journal: Codable, Equatable {
        var bootID: String
        var originals: [String: [NativeKeyMapping]] = [:]
    }
    private let backend: any MacBookKeyboardMappingBackend
    private let defaults: UserDefaults
    private let journalKey = "macbook.fnControl.journal.v1"
    private let journalURL: URL
    private var journal: Journal
    private var persistedJournal: Journal?
    private var enabled = false
    private var permitted = true
    private var observing = false
    public private(set) var status = MacBookKeyboardMappingStatus()
    public var onChange: ((MacBookKeyboardMappingStatus) -> Void)?
    public var onDiagnostic: ((String) -> Void)?

    public init(backend: (any MacBookKeyboardMappingBackend)? = nil, defaults: UserDefaults = .standard,
                journalURL: URL? = nil) {
        let backend = backend ?? NativeMacBookKeyboardBackend()
        self.backend = backend; self.defaults = defaults
        self.journalURL = journalURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WindowsMacBridge/fn-control-journal.json")
        journal = Journal(bootID: backend.bootID)
        if let data = PrivateMappingJournal.load(self.journalURL) ?? defaults.data(forKey: journalKey),
           let stored = try? JSONDecoder().decode(Journal.self, from: data), stored.bootID == backend.bootID,
           stored.originals.count <= 128 {
            journal = stored
        }
    }

    /// The advanced HID backend already swaps Fn/Control, so it must not run this native swap too.
    public func configure(enabled: Bool, eventTapBackend: Bool = true, sessionActive: Bool = true) {
        self.enabled = enabled
        permitted = eventTapBackend && sessionActive
        refresh()
    }

    private func updateObservation() {
        let needed = enabled && permitted && backend.portable
        if needed && !observing {
            observing = backend.observeChanges { [weak self] in self?.refresh() }
        } else if !needed && observing {
            backend.stopObserving(); observing = false
        }
    }

    public func refresh() {
        // Manual/lifecycle rechecks retry a failed registration. No timer is
        // needed, and desktop Macs never register an unused keyboard observer.
        updateObservation()
        let old = status
        var next = MacBookKeyboardMappingStatus()
        let shouldApply = enabled && permitted
        if (!enabled || !backend.portable) && journal.originals.isEmpty {
            next.summary = enabled ? "等待本機 MacBook 內建鍵盤；外接／通用控制鍵盤保持原樣"
                : "已關閉；已還原本程式的交換"
            _ = saveJournal()
            publish(next, previous: old)
            return
        }
        guard let services = backend.services() else {
            next.issue = "無法讀取鍵盤服務；還原紀錄已保留，請重新檢查。"
            next.restorePending = !shouldApply && !journal.originals.isEmpty
            next.summary = next.issue!
            publish(next, previous: old)
            return
        }
        // Registry IDs are valid only for this boot. Removed services have lost their mappings.
        let liveIDs = Set(services.map { String($0.identity.registryID) })
        journal.originals = journal.originals.filter { liveIDs.contains($0.key) }
        for service in services where service.identity.isLocalMacBookKeyboard(portable: backend.portable) {
            let id = service.identity.registryID, key = String(id)
            guard let current = service.userMapping, let modifiers = service.modifierMapping else {
                next.issue = "鍵盤映射格式無法確認；已保留原設定。"; continue
            }
            if !shouldApply {
                restore(serviceID: id, current: current, next: &next)
                continue
            }
            guard !backend.bootID.isEmpty && observing else {
                restore(serviceID: id, current: current, next: &next)
                next.issue = "無法建立鍵盤通知或開機身分；未套用交換。"; continue
            }
            if MacBookFnControlMapping.hasModifierConflict(modifiers) {
                restore(serviceID: id, current: current, next: &next)
                next.issue = "系統修飾鍵已有 Fn／Ctrl 映射；請先還原該鍵盤，避免重複交換。"; continue
            }
            if journal.originals[key] != nil && MacBookFnControlMapping.containsSwap(current) {
                next.activeDevices += 1; continue
            }
            if MacBookFnControlMapping.hasUserConflict(current) {
                restore(serviceID: id, current: current, next: &next)
                next.issue = "其他映射正在使用 Fn／Ctrl；已停止交換並保留外部修改。"; continue
            }
            guard backend.keysNeutral else {
                next.awaitingNeutral = true
                next.issue = "請放開所有按鍵後套用 Fn／Ctrl 交換。"; continue
            }
            let original = current.filter { MacBookFnControlMapping.owns($0.source) }
            // Save ownership before mutation so a crash can be recovered on the next launch.
            journal.originals[key] = original
            guard saveJournal() else {
                next.issue = "無法保存還原紀錄；未修改鍵盤。"; continue
            }
            let desired = MacBookFnControlMapping.applying(to: current)
            if backend.write(desired, serviceID: id), verified(id: id, mapping: desired) {
                next.activeDevices += 1
            } else {
                // A successful property setter alone is not proof the system accepted it.
                if let actual = backend.services()?.first(where: { $0.identity.registryID == id })?.userMapping {
                    restore(serviceID: id, current: actual, next: &next)
                }
                next.issue = "macOS 未接受或無法驗證 Fn／Ctrl 交換；請檢查授權並重新檢查。"
            }
        }
        _ = saveJournal()
        next.restorePending = !shouldApply && !journal.originals.isEmpty
        if next.activeDevices > 0 { next.summary = "已交換 Fn ↔ 左 Ctrl（\(next.activeDevices) 個內建鍵盤）" }
        else if !enabled { next.summary = next.issue == nil ? "已關閉；已還原本程式的交換" : "還原待處理" }
        else if !permitted { next.summary = "暫停原生交換（HID 後端或 Session 暫停）" }
        else if let issue = next.issue { next.summary = issue }
        else { next.summary = "等待本機 MacBook 內建鍵盤；外接／通用控制鍵盤保持原樣" }
        publish(next, previous: old)
    }

    private func publish(_ next: MacBookKeyboardMappingStatus, previous: MacBookKeyboardMappingStatus) {
        status = next
        if previous != next { onChange?(next); onDiagnostic?(next.summary) }
    }

    public func stop() {
        enabled = false
        backend.stopObserving(); observing = false
        refresh()
    }
    private func verified(id: UInt64, mapping: [NativeKeyMapping]) -> Bool {
        guard let actual = backend.services()?.first(where: { $0.identity.registryID == id })?.userMapping else { return false }
        return Set(actual.map { "\($0.source):\($0.destination)" }) == Set(mapping.map { "\($0.source):\($0.destination)" })
    }
    private func restore(serviceID: UInt64, current: [NativeKeyMapping], next: inout MacBookKeyboardMappingStatus) {
        let key = String(serviceID)
        guard let original = journal.originals[key] else { return }
        let restored = MacBookFnControlMapping.restoring(current, original: original)
        guard restored == current || backend.keysNeutral else {
            next.awaitingNeutral = true
            next.issue = "請放開所有按鍵後還原 Fn／Ctrl 交換。"; return
        }
        if restored == current || (backend.write(restored, serviceID: serviceID) && verified(id: serviceID, mapping: restored)) {
            journal.originals.removeValue(forKey: key)
        } else { next.issue = "鍵盤交換尚未還原；請按重新檢查，或重新開機清除暫存映射。" }
    }
    private func saveJournal() -> Bool {
        // Compare values, not JSON byte order. Only cache a successful durable
        // save; changed ownership must still be persisted before HID mutation.
        guard persistedJournal != journal else { return true }
        if journal.originals.isEmpty {
            guard PrivateMappingJournal.remove(journalURL) else { return false }
            if defaults.object(forKey: journalKey) != nil { defaults.removeObject(forKey: journalKey) }
            persistedJournal = journal
            return true
        }
        guard let data = try? JSONEncoder().encode(journal) else { return false }
        guard PrivateMappingJournal.write(data, to: journalURL) else { return false }
        // Retain a legacy mirror for migration only; the durable file is authoritative.
        defaults.set(data, forKey: journalKey)
        persistedJournal = journal
        return true
    }
}
