import Foundation

public enum DriverApproval {
    public static func isRegistered(in systemExtensionList: String) -> Bool {
        systemExtensionList.split(separator: "\n").contains { line in
            let fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            return fields.count >= 6 && fields[2] == "G43BCU2T37" &&
                fields[3].split(separator: " ").first == "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
        }
    }
    public static func isEnabled(in systemExtensionList: String) -> Bool {
        systemExtensionList.split(separator: "\n").contains { line in
            let fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 6, fields[2] == "G43BCU2T37",
                  fields[3].split(separator: " ").first == "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice" else { return false }
            return fields[0] == "*" && fields[1] == "*" && fields[5] == "[activated enabled]"
        }
    }
}
