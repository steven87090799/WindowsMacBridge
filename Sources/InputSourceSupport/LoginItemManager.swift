// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import ServiceManagement

enum LoginItemState: String {
    case enabled = "Enabled"
    case pendingApproval = "Pending Approval"
    case off = "Off"
}

enum LoginItemManager {
    static var service: SMAppService { SMAppService.mainApp }

    static var state: LoginItemState {
        switch service.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .pendingApproval
        case .notRegistered, .notFound:
            .off
        @unknown default:
            .off
        }
    }

    static var isEnabled: Bool { state == .enabled }
    static var isRegistered: Bool { state != .off }
    static var requiresApproval: Bool { state == .pendingApproval }

    static var statusDescription: String {
        switch service.status {
        case .notRegistered: "Off"
        case .enabled: "Enabled"
        case .requiresApproval: "Pending Approval"
        case .notFound: "Off（找不到此 App 的登入項目）"
        @unknown default: "Off（未知狀態）"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard state == .off else { return }
            try service.register()
        } else {
            guard state != .off else { return }
            try service.unregister()
        }
        FileLogger.shared.log("Login item \(enabled ? "enabled" : "disabled"): \(statusDescription)")
    }
}
