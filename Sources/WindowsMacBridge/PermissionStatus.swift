import AppKit
@preconcurrency import ApplicationServices
import FinderSync
import ServiceManagement
import BridgeCore

/// Read-only checks for this running app. Reading a status never requests access.
@MainActor enum PermissionStatus {
    static func current() -> PermissionSnapshot {
        PermissionSnapshot(accessibility: AXIsProcessTrusted(),
             posting: CGPreflightPostEventAccess(),
             listening: CGPreflightListenEventAccess(),
             screenRecording: CGPreflightScreenCaptureAccess(),
             finderExtension: FIFinderSyncController.isExtensionEnabled,
             loginItem: SMAppService.mainApp.status == .enabled)
    }

}
