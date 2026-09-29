import AppKit
@preconcurrency import ApplicationServices
import FinderSync
import ServiceManagement

/// Read-only checks for this running app. Reading a status never requests access.
@MainActor struct PermissionStatus: Equatable {
    var accessibility = false
    var posting = false
    var listening = false
    var screenRecording = false
    var finderExtension = false
    var loginItem = false

    static func current() -> Self {
        Self(accessibility: AXIsProcessTrusted(),
             posting: CGPreflightPostEventAccess(),
             listening: CGPreflightListenEventAccess(),
             screenRecording: CGPreflightScreenCaptureAccess(),
             finderExtension: FIFinderSyncController.isExtensionEnabled,
             loginItem: SMAppService.mainApp.status == .enabled)
    }

    var diagnosticText: String {
        [("Accessibility", accessibility), ("Event posting", posting),
         ("Input Monitoring", listening), ("Screen Recording", screenRecording),
         ("Finder extension", finderExtension), ("Login item", loginItem)]
            .map { "\($0.0): \($0.1 ? "granted/enabled" : "not granted/disabled")" }
            .joined(separator: "\n")
    }
}
