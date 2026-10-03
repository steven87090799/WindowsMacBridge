import AppKit
import ApplicationServices
import SwiftUI
import BridgePlatform
import BridgeCore
import HIDRuntime
import Darwin
import InputSourceSupport
import InputSourceCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var controller: BridgeController!
    private var item: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var lastTooltip: String?
    private var lastActive: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        controller = BridgeController()
        if controller.bundledInstallerAvailable && Bundle.main.bundleURL.standardizedFileURL.path != "/Applications/WindowsMacBridge.app" {
            let alert = NSAlert()
            alert.messageText = "請先將 App 拖進「應用程式」"
            alert.informativeText = "將 WindowsMacBridge 拖進「應用程式」，再從那裡開啟。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        item.button?.image = BrandAssets.active
        item.button?.setAccessibilityLabel("WindowsMacBridge")
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self; item.menu = menu
        controller.onStatusChange = { [weak self] in
            guard let self else { return }
            updateStatusItem()
        }
        controller.start()
        if !controller.permissions.keyboardControlGranted ||
            !controller.settings.enabled || controller.backgroundInstallationNeeded || controller.preparedSetupThisLaunch ||
            CommandLine.arguments.contains("--permission-relaunch") { showSettings() }
    }
    private func updateStatusItem() {
        let tooltip = controller.summary + " · " + controller.sourceStatus.summary
        if tooltip != lastTooltip { item.button?.toolTip = tooltip; lastTooltip = tooltip }
        let active = controller.settings.enabled && !controller.paused && !controller.status.emergencyPaused
        if active != lastActive {
            item.button?.image = active ? BrandAssets.active : BrandAssets.paused
            lastActive = active
        }
    }
    func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "WindowsMacBridge")
        let settings = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "結束 WindowsMacBridge", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編輯")
        for (title, selector, key) in [("復原", "undo:", "z"), ("重做", "redo:", "Z"),
                                      ("剪下", "cut:", "x"), ("複製", "copy:", "c"),
                                      ("貼上", "paste:", "v"), ("全選", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "視窗")
        windowMenu.addItem(NSMenuItem(title: "關閉視窗", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu; mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        // A hidden NSHostingView still observes @Published values and performs layout.
        window.contentView = nil
        window.delegate = nil
        settingsWindow = nil
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        label("WindowsMacBridge \(AppBuildInfo.current.versionLabel) · \(AppBuildInfo.current.shortRevision)", in: menu)
        label(controller.summary, in: menu)
        label("App: \(controller.context.displayName)", in: menu)
        label("Profile: \(controller.context.mode.title)", in: menu)
        menu.addItem(.separator())
        let enabled = action("啟用 Windows Mode", #selector(toggleEnabled), in: menu)
        enabled.state = controller.settings.enabled ? .on : .off
        action("恢復／重啟引擎", #selector(resume), in: menu)
        let pause = NSMenuItem(title: "暫停所有輸入輔助", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for minutes in [5, 15, 60] {
            let entry = action("\(minutes) 分鐘", #selector(pauseTimed(_:)), in: submenu)
            entry.tag = minutes
        }
        action("直到 App 重啟", #selector(pauseUntilRestart), in: submenu)
        pause.submenu = submenu; menu.addItem(pause)
        menu.addItem(.separator())
        label("輸入法：\(controller.sourceStatus.summary)", in: menu)
        let guardItem = action("啟用唯音輸入法守護", #selector(toggleGuard), in: menu)
        guardItem.state = controller.sourceStatus.enabled ? .on : .off
        let detectionPause = NSMenuItem(title: "暫停輸入法偵測", action: nil, keyEquivalent: "")
        let detectionMenu = NSMenu()
        for duration in GuardPauseDuration.allCases {
            let entry = action(duration.title, #selector(pauseSourceDetection(_:)), in: detectionMenu)
            entry.representedObject = duration.rawValue
        }
        detectionPause.submenu = detectionMenu; menu.addItem(detectionPause)
        if controller.sourceStatus.detectionPaused {
            action("恢復輸入法偵測", #selector(resumeSourceDetection), in: menu)
        }
        let chinese = action("切換至唯音繁體", #selector(selectChinese), in: menu)
        let english = action("切換至 ABC", #selector(selectEnglish), in: menu)
        chinese.isEnabled = controller.sourceStatus.suspension == nil
        english.isEnabled = controller.sourceStatus.suspension == nil
        menu.addItem(.separator())
        action("設定／Profiles／診斷…", #selector(showSettings), in: menu)
        action("結束 WindowsMacBridge", #selector(quit), in: menu)
    }
    private func label(_ title: String, in menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false; menu.addItem(entry)
    }
    @discardableResult private func action(_ title: String, _ selector: Selector, in menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self; menu.addItem(entry); return entry
    }
    @objc private func toggleGuard() { controller.inputSources.setEnabled(!controller.sourceStatus.enabled) }
    @objc private func selectChinese() { controller.inputSources.select(.vChewing) }
    @objc private func selectEnglish() { controller.inputSources.select(.abc) }
    @objc private func pauseSourceDetection(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let duration = GuardPauseDuration(rawValue: raw) else { return }
        controller.inputSources.pauseDetection(duration)
    }
    @objc private func resumeSourceDetection() { controller.inputSources.resumeDetection() }
    @objc private func toggleEnabled() { controller.setEnabled(!controller.settings.enabled) }
    @objc private func resume() { controller.resume() }
    @objc private func pauseTimed(_ item: NSMenuItem) { controller.pause(minutes: item.tag) }
    @objc private func pauseUntilRestart() { controller.pause(minutes: nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showSettings() {
        controller.refreshPermissions()
        controller.settingsPage = .permissions
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "WindowsMacBridge"
            window.contentMinSize = NSSize(width: 730, height: 600)
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main enum WindowsMacBridgeMain {
    @MainActor static func main() {
        if HIDRuntimeCommand.handle(Array(CommandLine.arguments.dropFirst())) { return }
        guard geteuid() != 0 else { exit(77) }
        if CommandLine.arguments.contains("--self-check") {
            do {
                let registry = try ApplicationRegistry()
                if Bundle.main.bundleURL.pathExtension == "app" {
                    let extensionURL = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/WindowsMacBridgeFinderSync.appex")
                    guard let finder = Bundle(url: extensionURL),
                          finder.infoDictionary?["CFBundleIdentifier"] as? String == "local.WindowsMacBridge.FinderSync",
                          finder.executableURL != nil else {
                        print("WindowsMacBridge self-check failed: Finder Sync extension missing.")
                        exit(1)
                    }
                    guard finder.infoDictionary?["WMBFinderSignalVersion"] as? Int == FinderModeChannel.version,
                          finder.infoDictionary?["CFBundleShortVersionString"] as? String == Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                          finder.infoDictionary?["CFBundleVersion"] as? String == Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
                        print("WindowsMacBridge self-check failed: Finder signal protocol mismatch.")
                        exit(1)
                    }
                }
                print("\(AppBuildInfo.current.diagnosticText)\nBundled registry loaded (\(registry.entries.count) entries); no event tap or capture started.")
            } catch {
                print("WindowsMacBridge self-check failed: registry unavailable.")
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--version") {
            print(AppBuildInfo.current.diagnosticText)
            return
        }
        if CommandLine.arguments.contains("--diagnose-permissions") {
            print("\(AppBuildInfo.current.diagnosticText)\n\(PermissionStatus.current().diagnosticText)")
            print("CLI permission checks may use the launching terminal's TCC identity. The running App's permission page is authoritative for that App.")
            return
        }
        if CommandLine.arguments.contains("--diagnose-input-sources") {
            print(InputSourceCoordinator.discoveryReport())
            return
        }
        if CommandLine.arguments.contains("--diagnose-backend") {
            print(HIDDeviceInventory.report())
            print(NativeMacBookKeyboardBackend().diagnosticReport())
            return
        }
        if CommandLine.arguments.contains("--diagnose-input-producers") {
            print(RemoteProcessResolver.metadataReport())
            return
        }
        guard InputSourceCoordinator.acquireSingleInstance() else { return }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
