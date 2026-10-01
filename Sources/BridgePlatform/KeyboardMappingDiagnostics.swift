import Foundation
import BridgeCore

/// State transitions only; never key events, text, clipboard, or other applications' data.
public enum KeyboardMappingDiagnostics {
    private static let logger = BoundedDiagnosticLogger(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WindowsMacBridge/KeyboardMapping.log"))
    public static func append(_ message: String) {
        logger.log(message)
    }
}
