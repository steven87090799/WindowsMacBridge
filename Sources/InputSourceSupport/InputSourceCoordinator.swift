import AppKit
import Carbon
import ServiceManagement
import BridgeCore
import InputSourceCore

public struct InputSourceStatus: Equatable, Sendable {
    public var enabled = false
    public var hotkeyEnabled = false
    public var hotkeyRegistered = false
    public var selectionInProgress = false
    public var preset = HotkeyPreset.controlOptionCommandSpace
    public var desired = DesiredInputSource.vChewing
    public var summary = "輸入法守護未啟動"
    public var current = "unknown"
    public var traditional = "尚未偵測"
    public var abc = "尚未偵測"
    public var issue: String?
    public var suspension: InputSourceSuspension?
    public var debounceMilliseconds = 400
    public var startupDelayMilliseconds = 1_500
    public var loginStatus = "Off"
    public var loginRegistered = false
    public var loginIssue: String?
    public init() {}
}

/// One main-actor boundary around the imported main-queue Carbon/TIS implementation.
/// This object never sees keyboard events and never creates an event tap.
@MainActor public final class InputSourceCoordinator {
    public var onChange: ((InputSourceStatus) -> Void)?
    /// Revalidated immediately before TIS selection / hotkey handling, outside the tap.
    public var liveSelectionAllowed: () -> Bool = { false }
    private let controller: GuardController
    private var hotkey: HotkeyManager?
    private var started = false
    private var hotkeyRegistered = false
    private var hotkeyIssue: String?
    private var issue: String?
    private var loginIssue: String?
    private var suspension: InputSourceSuspension? = .unknownApplication
    private let defaults = UserDefaults.standard
    private let hotkeyEnabledKey = "inputSource.hotkeyEnabled"

    public init() {
        AppSettings.registerDefaults()
        controller = GuardController()
        controller.selectionAllowed = { [weak self] in
            guard let self else { return false }
            return self.started && self.suspension == nil && self.liveSelectionAllowed()
        }
        controller.onStateChange = { [weak self] in self?.emit() }
        controller.onIssue = { [weak self] message in self?.issue = message; self?.emit() }
    }

    public func start() {
        guard !started else { return }
        started = true
        controller.setHostSuspended(suspension != nil)
        controller.start()
        synchronizeHotkey()
        emit()
    }

    public func stop() {
        guard started else { return }
        started = false
        hotkey?.stop(); hotkey = nil; hotkeyRegistered = false
        controller.stop()
        FileLogger.shared.flush()
    }

    public func updateProtection(_ reason: InputSourceSuspension?) {
        guard suspension != reason else { return }
        suspension = reason
        guard started else { return }
        // Unregister first, before resuming any queued source reconciliation.
        synchronizeHotkey()
        controller.setHostSuspended(reason != nil)
        emit()
    }

    public func setEnabled(_ enabled: Bool) { issue = nil; controller.setGuardEnabled(enabled); emit() }
    public func select(_ source: DesiredInputSource) {
        guard started, suspension == nil, liveSelectionAllowed() else { return }
        issue = nil; controller.request(source); emit()
    }
    public func toggleSource() { select(controller.desired == .vChewing ? .abc : .vChewing) }
    public func setHotkeyEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: hotkeyEnabledKey); synchronizeHotkey(); emit()
    }
    public func setPreset(_ preset: HotkeyPreset) {
        // Register before saving, preserving the previous working binding on failure.
        if hotkeyRegistered, let hotkey {
            let status = hotkey.register(preset)
            guard status == noErr else {
                hotkeyRegistered = hotkey.isRegistered
                hotkeyIssue = "快捷鍵無法註冊（OSStatus \(status)）；已嘗試恢復原設定。"
                emit(); return
            }
        }
        AppSettings.setHotkeyPreset(preset); hotkeyIssue = nil; emit()
    }
    public func setDebounce(_ milliseconds: Int) {
        AppSettings.setDebounce(milliseconds); controller.debounceSettingChanged(); emit()
    }
    public func setStartupDelay(_ milliseconds: Int) { AppSettings.setStartupDelay(milliseconds); emit() }
    public func rediscover() { issue = nil; controller.refreshAndReconcile(reason: "User refreshed input sources"); emit() }
    public func setLoginEnabled(_ enabled: Bool) {
        do { try LoginItemManager.setEnabled(enabled); loginIssue = nil }
        catch { loginIssue = "登入項目更新失敗：\(error.localizedDescription)。請將 App 放在 Applications 後再設定。" }
        emit()
    }
    public var loginIsRegistered: Bool { LoginItemManager.isRegistered }
    public var loginIsActive: Bool { LoginItemManager.isEnabled }
    public var loginStatusText: String { LoginItemManager.statusDescription }
    @discardableResult public func ensureLoginEnabled() -> Bool {
        setLoginEnabled(true)
        return LoginItemManager.isRegistered
    }
    public func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    public var status: InputSourceStatus {
        var result = InputSourceStatus()
        result.enabled = controller.isEnabled
        result.hotkeyEnabled = defaults.bool(forKey: hotkeyEnabledKey)
        result.hotkeyRegistered = hotkeyRegistered
        result.selectionInProgress = controller.selectionInProgress
        result.preset = AppSettings.hotkeyPreset
        result.desired = controller.desired
        result.suspension = suspension
        result.summary = suspension?.rawValue ?? controller.statusText
        result.current = controller.inputSources.currentIdentifier ?? "unknown"
        result.traditional = controller.inputSources.discovery.traditional?.summary ?? "未找到唯音繁體"
        result.abc = controller.inputSources.discovery.abc?.summary ?? "未找到 ABC"
        result.issue = issue ?? hotkeyIssue ?? (controller.isEnabled ? controller.issueDescription : nil)
        result.debounceMilliseconds = AppSettings.debounceMilliseconds
        result.startupDelayMilliseconds = AppSettings.startupDelayMilliseconds
        result.loginStatus = LoginItemManager.statusDescription
        result.loginRegistered = LoginItemManager.isRegistered
        result.loginIssue = loginIssue
        return result
    }
    public var diagnostics: String { controller.diagnostics + "\nHost policy: \(suspension?.rawValue ?? "Local")\nHotkey registered: \(hotkeyRegistered)" }
    public var recentLog: String { FileLogger.shared.recentText() }

    public static func acquireSingleInstance() -> Bool {
        if SingleInstanceGuard.shared.acquire() { return true }
        SingleInstanceGuard.shared.activateExistingInstanceIfPossible()
        return false
    }
    /// Enumerates metadata only: no source selection, hotkey registration or event tap.
    public static func discoveryReport() -> String {
        let manager = InputSourceManager()
        let found = manager.rediscover(logChanges: false)
        return "Current: \(manager.currentIdentifier ?? "unknown")\nSecure Input: \(IsSecureEventInputEnabled())\nvChewing Traditional: \(found.traditional?.summary ?? "not found")\nABC: \(found.abc?.summary ?? "not found")"
    }
    private func synchronizeHotkey() {
        guard started, suspension == nil, defaults.bool(forKey: hotkeyEnabledKey) else {
            hotkey?.suspend(); hotkeyRegistered = false; return
        }
        if hotkey == nil {
            hotkey = HotkeyManager()
            hotkey?.onHotkey = { [weak self] in
                guard let self, self.hotkeyRegistered,
                      self.defaults.bool(forKey: self.hotkeyEnabledKey) else { return }
                self.toggleSource()
            }
        }
        guard let hotkey else { return }
        let status = hotkey.register(AppSettings.hotkeyPreset)
        hotkeyRegistered = hotkey.isRegistered
        hotkeyIssue = status == noErr ? nil : "快捷鍵無法註冊（OSStatus \(status)），請選另一組快捷鍵。"
    }
    private func emit() { onChange?(status) }
}
