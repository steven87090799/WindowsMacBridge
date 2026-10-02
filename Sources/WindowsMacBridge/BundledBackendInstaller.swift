import AppKit
import HIDProtocol
import Security

/// Explicit setup only. No polling, automatic elevation or permission changes.
@MainActor enum BundledBackendInstaller {
    static var available: Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        return FileManager.default.fileExists(atPath: resources.appendingPathComponent("BackendPayload/InstallBackend.sh").path)
    }
    static var needsInstallation: Bool {
        let runtimeURL = URL(fileURLWithPath: HIDService.root + "/WindowsMacBridge.app")
        let runtime = Bundle(url: runtimeURL)
        return Bundle.main.bundleURL.standardizedFileURL.path != "/Applications/WindowsMacBridge.app" ||
            runtime?.object(forInfoDictionaryKey: "CFBundleVersion") as? String != AppBuildInfo.current.buildNumber ||
            !runtimeIdentityMatches ||
            FileManager.default.fileExists(atPath: HIDService.root + "/BridgeHIDHelper.app") ||
            !FileManager.default.fileExists(atPath: HIDService.root + "/controller.plist") ||
            !FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/local.WindowsMacBridge.HIDHelper.plist")
    }
    private static let runtimeIdentityMatches: Bool = {
        guard let current = PermissionStatus.codeIdentity else { return false }
        return signedHash(URL(fileURLWithPath: HIDService.root + "/WindowsMacBridge.app")) == current
    }()
    private static func signedHash(_ url: URL) -> String? {
        var code: SecStaticCode?, info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    static func launch() throws {
        guard available, let resources = Bundle.main.resourceURL else {
            throw NSError(domain: "WindowsMacBridge.Setup", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "這份 App 未包含背景元件；請使用完整單一 App 安裝版。"])
        }
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [resources.appendingPathComponent("LaunchEmbeddedInstall.sh").path, Bundle.main.bundleURL.path]
        launcher.standardInput = FileHandle.nullDevice
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
        // Close only our installed copy normally; the launcher waits for its
        // keyboard cleanup before replacing anything. Never force-quit it.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.WindowsMacBridge")
            where app.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                app.bundleURL?.standardizedFileURL.path == "/Applications/WindowsMacBridge.app" {
            app.terminate()
        }
        // The independent launcher stages this bundle, waits for normal shutdown,
        // then asks macOS for administrator authentication and relaunches it.
        NSApp.terminate(nil)
    }
}
