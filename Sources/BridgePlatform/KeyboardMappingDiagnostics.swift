import Foundation

/// State transitions only; never key events, text, clipboard, or other applications' data.
public enum KeyboardMappingDiagnostics {
    public static func append(_ message: String) {
        let manager = FileManager.default
        let url = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WindowsMacBridge/KeyboardMapping.log")
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue >= 262_144 {
                let previous = url.appendingPathExtension("1")
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                try manager.moveItem(at: url, to: previous)
            }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let data = Data("\(timestamp) \(message)\n".utf8)
            if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
        } catch { /* Mapping state and errors remain visible in the settings window. */ }
    }
}
