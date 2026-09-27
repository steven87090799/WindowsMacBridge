import AppKit
import ApplicationServices
import SwiftUI
import BridgePlatform
import InputSourceSupport

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: BridgeController!
    private var item: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        controller = BridgeController()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "W唯"
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self; item.menu = menu
        controller.onStatusChange = { [weak self] in
            guard let self else { return }
            item.button?.toolTip = controller.summary + " · " + controller.sourceStatus.summary
            item.button?.title = controller.settings.enabled && !controller.paused && !controller.status.emergencyPaused ? "W唯" : (controller.sourceStatus.enabled ? "唯" : "WⅡ")
        }
        controller.start()
        if !AXIsProcessTrusted() || !controller.settings.enabled { showSettings() }
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
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
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
    @objc private func toggleEnabled() { controller.setEnabled(!controller.settings.enabled) }
    @objc private func resume() { controller.resume() }
    @objc private func pauseTimed(_ item: NSMenuItem) { controller.pause(minutes: item.tag) }
    @objc private func pauseUntilRestart() { controller.pause(minutes: nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "WindowsMacBridge"
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main enum WindowsMacBridgeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-check") {
            do {
                let registry = try ApplicationRegistry()
                print("WindowsMacBridge 0.4.0 HID preview: bundled registry loaded (\(registry.entries.count) entries); no event tap or capture started.")
            } catch {
                print("WindowsMacBridge self-check failed: registry unavailable.")
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--diagnose-input-sources") {
            print(InputSourceCoordinator.discoveryReport())
            return
        }
        if CommandLine.arguments.contains("--diagnose-backend") {
            print(HIDDeviceInventory.report())
            return
        }
        guard InputSourceCoordinator.acquireSingleInstance() else { return }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
