import AppKit
@preconcurrency import ApplicationServices
import FinderSync
import ServiceManagement
import Security
import IOKit.hid
import BridgeCore

/// Read-only checks for this running app. Reading a status never requests access.
@MainActor enum PermissionStatus {
    /// Remember explicit folder requests only for this exact signed App. This
    /// token is consent to recheck, never a saved TCC grant.
    static let codeIdentity: String? = {
        var runningCode: SecCode?, code: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &runningCode) == errSecSuccess, let runningCode,
              SecCodeCopyStaticCode(runningCode, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }()
    static func current(advanced: Bool = false) -> PermissionSnapshot {
        PermissionSnapshot(accessibility: AXIsProcessTrusted(),
             posting: CGPreflightPostEventAccess(),
             listening: CGPreflightListenEventAccess() && (!advanced || IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted),
             screenRecording: CGPreflightScreenCaptureAccess(),
             finderExtension: advanced && FIFinderSyncController.isExtensionEnabled,
             loginItem: SMAppService.mainApp.status == .enabled)
    }

}
