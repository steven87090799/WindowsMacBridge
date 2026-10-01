// Adapted from VChewingGuard (MIT); log admission and disk work are bounded.
import Foundation
import BridgeCore

final class FileLogger {
    static let shared = FileLogger()
    private let logger: BoundedDiagnosticLogger
    private let url: URL
    private init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowsMacBridge/InputSources.log")
        logger = BoundedDiagnosticLogger(url: url)
    }
    func log(_ message: String) { logger.log(message) }
    var path: String { url.path }
    func readRecent(_ completion: @escaping @Sendable (String) -> Void) { logger.readRecent(completion) }
    func flush() { logger.flush() }
}
