import Foundation
import Security

/// Per-message peer requirement for the single controller App.
/// An accept-time PID lookup can be raced by PID reuse or exec after connect;
/// NSXPCConnection checks this requirement against each sender's audit token.
public enum ControllerCodeRequirement {
    public static func make(identifier: String, cdhash: Data) -> String? {
        // Only reverse-DNS characters; the value is embedded in requirement text.
        let allowed = identifier.utf8.allSatisfy {
            $0 == 0x2e || $0 == 0x2d || $0 == 0x5f || (0x30...0x39).contains($0) ||
            (0x41...0x5a).contains($0) || (0x61...0x7a).contains($0)
        }
        guard cdhash.count == 20, !identifier.isEmpty, identifier.utf8.count <= 255, allowed else { return nil }
        let hex = cdhash.map { String(format: "%02x", $0) }.joined()
        let text = "identifier \"\(identifier)\" and cdhash H\"\(hex)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              requirement != nil else { return nil }
        return text
    }
}
