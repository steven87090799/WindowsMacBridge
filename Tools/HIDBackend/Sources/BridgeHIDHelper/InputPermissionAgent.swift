import AppKit
import IOKit.hid
import Darwin

/// Permission prompts belong to the logged-in user's GUI session. This mode
/// never constructs DeviceCapture, connects to the driver or opens a keyboard.
@MainActor final class InputPermissionAgent: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            // Give LaunchServices time to acknowledge this real Cocoa launch.
            // One deadline, no polling or resident permission agent.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
    }
    static func run() {
        guard geteuid() != 0, geteuid() == DeviceCapture.consoleUID() else { exit(77) }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let agent = InputPermissionAgent()
        application.delegate = agent
        withExtendedLifetime(agent) { application.run() }
    }
}
