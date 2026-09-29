import Foundation

/// Only the non-sensitive Finder menu toggle crosses processes. Sandboxed
/// senders use an object string and nil userInfo; no paths or clipboard payload.
public struct FinderModeChannel: Sendable {
    public static let current = FinderModeChannel(namespace: "local.WindowsMacBridge.FinderMode")
    public static let version = 1
    public let requestName: Notification.Name
    public let stateName: Notification.Name
    public init(namespace: String) {
        requestName = Notification.Name(namespace + ".request.v1")
        stateName = Notification.Name(namespace + ".state.v1")
    }
    public static let requestObject = "v1"
    public static func object(enabled: Bool) -> String { enabled ? "v1:enabled" : "v1:disabled" }
    public static func enabled(from object: Any?) -> Bool? {
        switch object as? String {
        case "v1:enabled": true
        case "v1:disabled": false
        default: nil
        }
    }
}
