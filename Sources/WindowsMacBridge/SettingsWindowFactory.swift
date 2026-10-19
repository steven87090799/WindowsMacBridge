import AppKit
import SwiftUI

/// One standard native window configuration for production and offline layouts.
@MainActor enum SettingsWindowFactory {
    static func make<Content: View>(content: Content) -> NSWindow {
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1000, height: 760))
        window.contentMinSize = NSSize(width: 730, height: 600)
        window.title = "WindowsMacBridge"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        return window
    }
}
