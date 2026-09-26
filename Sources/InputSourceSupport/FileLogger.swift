// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Foundation

final class FileLogger {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "WindowsMacBridge.inputSources.logger")
    private let logURL: URL
    private let maximumBytes = 512 * 1_024
    private let timestampFormatter: ISO8601DateFormatter

    private init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowsMacBridge", isDirectory: true)
        logURL = logs.appendingPathComponent("InputSources.log")
        timestampFormatter = ISO8601DateFormatter()
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    }

    func log(_ message: String) {
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
                   (attributes[.size] as? NSNumber)?.intValue ?? 0 >= maximumBytes {
                    let previous = logURL.appendingPathExtension("1")
                    try? FileManager.default.removeItem(at: previous)
                    try? FileManager.default.moveItem(at: logURL, to: previous)
                }

                let timestamp = timestampFormatter.string(from: Date())
                let line = "[\(timestamp)] \(message)\n"
                guard let data = line.data(using: .utf8) else { return }

                if FileManager.default.fileExists(atPath: logURL.path) {
                    let file = try FileHandle(forWritingTo: logURL)
                    try file.seekToEnd()
                    try file.write(contentsOf: data)
                    try file.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                NSLog("WindowsMacBridge: input-source logging failed: %@", error.localizedDescription)
            }
        }
    }

    var path: String { logURL.path }

    func recentText(maximumLines: Int = 150) -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: logURL),
                  let content = String(data: data, encoding: .utf8) else {
                return "尚無診斷記錄。"
            }
            return content.split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(maximumLines)
                .joined(separator: "\n")
        }
    }

    func flush() {
        queue.sync {}
    }
}
