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
    private var terminationTask: Task<Void, Never>?

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
        if !controller.permissions.keyboardControlGranted || !controller.permissions.listening ||
            !controller.settings.enabled || controller.backgroundInstallationNeeded || controller.preparedSetupThisLaunch ||
            CommandLine.arguments.contains("--permission-relaunch") { showSettings() }
    }
    private func updateStatusItem() {
        let tooltip = "WindowsMacBridge"
        if tooltip != lastTooltip { item.button?.toolTip = tooltip; lastTooltip = tooltip }
        let active = controller.isOperating
        if active != lastActive {
            item.button?.image = active ? BrandAssets.active : BrandAssets.paused
            lastActive = active
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        controller.prepareForTermination()
        terminationTask = Task { @MainActor [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            while !Task.isCancelled {
                if await controller.restoreNativeMappingForTermination() {
                    terminationTask = nil
                    sender.reply(toApplicationShouldTerminate: true)
                    return
                }
                guard !Task.isCancelled else { return }
                let alert = NSAlert()
                alert.messageText = "鍵盤交換尚未還原"
                alert.informativeText = "請放開所有按鍵後重試。若仍無法還原，請取消結束並在設定中重新檢查；還原紀錄已保留。"
                alert.addButton(withTitle: "放鍵後重試")
                alert.addButton(withTitle: "取消結束")
                if alert.runModal() != .alertFirstButtonReturn {
                    controller.cancelTermination()
                    terminationTask = nil
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        terminationTask?.cancel(); terminationTask = nil
        controller?.stop()
    }
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
        SettingsWindowFactory.releaseContent(of: window)
        window.delegate = nil
        settingsWindow = nil
    }
    func applicationDidHide(_ notification: Notification) {
        if let window = settingsWindow { SettingsWindowFactory.releaseContent(of: window) }
    }
    func applicationDidUnhide(_ notification: Notification) {
        if let window = settingsWindow, !window.isMiniaturized {
            restoreSettingsContent(of: window)
        }
    }
    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        SettingsWindowFactory.releaseContent(of: window)
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        restoreSettingsContent(of: window)
    }
    private func restoreSettingsContent(of window: NSWindow) {
        SettingsWindowFactory.restoreContent(of: window, content: SettingsView(controller: controller))
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let enabled = action("Windows 模式總開關", #selector(toggleEnabled), in: menu, symbol: "keyboard")
        enabled.state = controller.settings.enabled ? .on : .off
        action("恢復／重啟引擎", #selector(resume), in: menu, symbol: "arrow.clockwise")
        let pause = NSMenuItem(title: "暫停所有輸入輔助", action: nil, keyEquivalent: "")
        pause.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        let submenu = NSMenu()
        for minutes in [5, 15, 60] {
            let entry = action("\(minutes) 分鐘", #selector(pauseTimed(_:)), in: submenu)
            entry.tag = minutes
        }
        action("直到 App 重啟", #selector(pauseUntilRestart), in: submenu)
        pause.submenu = submenu; menu.addItem(pause)
        menu.addItem(.separator())
        let textCapture = action("截圖文字擷取…", #selector(captureScreenshotText), in: menu, symbol: "text.viewfinder")
        textCapture.isEnabled = controller.canCaptureScreenshotText
        if controller.screenshotStatus.isBusy { action("取消截圖／文字辨識", #selector(cancelScreenshot), in: menu) }
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
        action("設定…", #selector(showSettings), in: menu, symbol: "slider.horizontal.3")
        action("結束 WindowsMacBridge", #selector(quit), in: menu, symbol: "power")
    }
    private func label(_ title: String, in menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false; menu.addItem(entry)
    }
    @discardableResult private func action(_ title: String, _ selector: Selector, in menu: NSMenu, symbol: String? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        entry.target = self; menu.addItem(entry); return entry
    }
    @objc private func toggleGuard() { controller.inputSources.setEnabled(!controller.sourceStatus.enabled) }
    @objc private func captureScreenshotText() { controller.captureScreenshotText() }
    @objc private func cancelScreenshot() { controller.cancelScreenshot() }
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
            let window = SettingsWindowFactory.make(content: SettingsView(controller: controller))
            window.delegate = self
            window.center(); settingsWindow = window
        }
        if let window = settingsWindow {
            restoreSettingsContent(of: window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main enum WindowsMacBridgeMain {
    @MainActor static func main() {
        if HIDRuntimeCommand.handle(Array(CommandLine.arguments.dropFirst())) { return }
        guard geteuid() != 0 else { exit(77) }
        // Older private diagnostic commands must never accidentally start the GUI.
        if CommandLine.arguments.dropFirst().first == ScreenshotTextBudget.workerArgument { exit(64) }
        if FeatureResourceCheck.handle(Array(CommandLine.arguments.dropFirst())) { return }
        if FeatureVisualCheck.handle(Array(CommandLine.arguments.dropFirst())) { return }
        if FeatureUIResourceCheck.handle(Array(CommandLine.arguments.dropFirst())) { return }
        if CommandLine.arguments.contains("--self-check") {
            do {
                let registry = try ApplicationRegistry()
                if Bundle.main.bundleURL.pathExtension == "app" {
                    guard let worker = IsolatedScreenshotTextRecognizer.bundledExecutable(),
                          FileManager.default.isExecutableFile(atPath: worker.path) else {
                        print("WindowsMacBridge self-check failed: OCR helper missing.")
                        exit(1)
                    }
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
