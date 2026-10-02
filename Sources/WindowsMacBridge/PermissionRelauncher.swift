import Foundation

/// One explicit restart. No extra App instance, persistent helper or force quit.
@MainActor enum PermissionRelauncher {
    static func start() throws {
        guard Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/WindowsMacBridge.app",
              let script = Bundle.main.resourceURL?.appendingPathComponent("RelaunchApp.sh"),
              FileManager.default.fileExists(atPath: script.path) else {
            throw NSError(domain: "WindowsMacBridge.Relaunch", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "請結束 WindowsMacBridge，再從「應用程式」重新開啟。"])
        }
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        launcher.standardInput = FileHandle.nullDevice
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
    }
}
