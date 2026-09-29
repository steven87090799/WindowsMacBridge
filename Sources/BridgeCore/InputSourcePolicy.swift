/// Shared host policy for automatic TIS selection, manual requests and the Carbon hotkey.
/// Terminal/IDE protect their Control keys independently; input-source selection is allowed.
public enum InputSourceSuspension: String, Equatable, Sendable {
    case paused = "所有輸入輔助已暫停"
    case inactiveSession = "螢幕、系統或使用者 Session 暫停"
    case protectedApplication = "目前 App 的 Profile 暫停輸入法切換與快捷鍵"
    case unknownApplication = "無法確認前景 App，暫停輸入法切換"
}

public enum InputSourcePolicy {
    public static func suspension(context: ApplicationContext, isHostApp: Bool,
                                  paused: Bool, sessionActive: Bool) -> InputSourceSuspension? {
        if paused { return .paused }
        if !sessionActive { return .inactiveSession }
        if context.processID <= 0 || context.bundleID.isEmpty { return .unknownApplication }
        if isHostApp { return nil }
        switch context.mode {
        case .remoteWindows, .virtualMachine, .game, .disabled: return .protectedApplication
        case .macOS, .terminal, .ide: return nil
        }
    }
}
