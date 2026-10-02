@preconcurrency import ApplicationServices
import BridgeCore

/// Called exclusively by an explicit user action. Normal status checks never prompt.
@MainActor public enum KeyboardPermissionRequest {
    public static var settingsTitle: String {
        if #available(macOS 27.0, *) { return "裝置控制和資料取用" }
        return "輔助使用"
    }
    public static func plan(for current: PermissionSnapshot) -> [PermissionKind] {
        // Both capabilities share one system switch. Native requests can prompt
        // asynchronously, so issuing both in one click stacks system dialogs.
        if !current.posting { return [.posting] }
        if !current.accessibility { return [.accessibility] }
        return []
    }
    public static func perform(read: @MainActor () -> PermissionSnapshot,
                               request: @MainActor (PermissionKind) -> Bool = requestNative) -> PermissionSnapshot {
        for kind in plan(for: read()) { _ = request(kind) }
        // A request may return before the user responds, or may report success for
        // a different TCC identity. Only new native checks verify this process.
        return read()
    }
    public static func requestNative(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .posting: return CGRequestPostEventAccess()
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        default: return false
        }
    }
}
