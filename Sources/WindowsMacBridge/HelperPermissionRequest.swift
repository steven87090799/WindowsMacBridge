import AppKit
import Security
import HIDProtocol

/// Launch the installed helper's permission-only Cocoa mode as this user.
/// The root daemon remains independent and keeps its existing keyboard lease.
@MainActor final class HelperPermissionRequest {
    private var launching = false
    private var application: NSRunningApplication?
    func start(completion: @escaping @MainActor (Error?) -> Void) {
        guard !launching, application?.isTerminated != false else { completion(nil); return }
        let bundle = URL(fileURLWithPath: HIDService.root + "/BridgeHIDHelper.app")
        let binary = bundle.appendingPathComponent("Contents/MacOS/BridgeHIDHelper")
        for path in [URL(fileURLWithPath: HIDService.root), bundle, binary] {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
                  (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0 else {
                completion(Self.installationError); return
            }
        }
        var code: SecStaticCode?, info: CFDictionary?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], values[kSecCodeInfoIdentifier as String] as? String == HIDService.name,
              Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String == AppBuildInfo.current.buildNumber else {
            completion(Self.installationError); return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--request-input-access"]
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        launching = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { [weak self] app, error in
            Task { @MainActor in
                guard let self else { return }
                self.launching = false; self.application = app
                completion(error)
            }
        }
    }
    private static var installationError: Error {
        NSError(domain: "WindowsMacBridge.Setup", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "背景鍵盤元件尚未準備完成，請關閉並重新開啟 App 完成安裝。"])
    }
}
