import AppKit
import FinderSync

/// Finder supplies selected and targeted URLs only during menu construction/actions.
/// No background file scanning or pasteboard reads are needed.
final class FinderSync: FIFinderSync {
    private var modeEnabled = false
    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(modeChanged(_:)),
            name: FinderModeChannel.current.stateName, object: nil)
        requestMode()
        FIFinderSyncController.default().directoryURLs = []
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self) }
    override func beginObservingDirectory(at url: URL) { requestMode() }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        requestMode()
        guard finderEnabled, menuKind != .toolbarItemMenu else { return nil }
        let menu = NSMenu(title: "WindowsMacBridge")
        menu.autoenablesItems = false
        let controller = FIFinderSyncController.default()
        let selected = Array((controller.selectedItemURLs() ?? []).prefix(1025))
        let targeted = controller.targetedURL()
        let folder = FinderPathSelection.folder(targetedURL: targeted, selectedURLs: selected,
            itemTarget: menuKind == .contextualMenuForItems)
        let selectedPaths = FinderPathSelection.selected(selected)
        let folderItem = item("複製目前資料夾路徑", #selector(copyFolder(_:)))
        folderItem.representedObject = folder
        folderItem.isEnabled = folder != nil
        menu.addItem(folderItem)
        let selectedItem = item("複製選取項目完整路徑", #selector(copySelected(_:)))
        selectedItem.representedObject = selectedPaths
        selectedItem.isEnabled = selectedPaths != nil
        menu.addItem(selectedItem)
        let displayPath = FinderPathSelection.displayed(selectedURLs: selected,
            targetedURL: targeted,
            itemTarget: menuKind == .contextualMenuForItems)
        let displayItem = NSMenuItem(title: "顯示目前資料夾路徑", action: nil, keyEquivalent: "")
        displayItem.isEnabled = displayPath != nil
        if let displayPath {
            let pathMenu = NSMenu(title: "完整 POSIX 路徑")
            let pathItem = NSMenuItem(title: displayPath, action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            pathMenu.addItem(pathItem)
            let copyItem = item("複製此路徑", #selector(copyDisplayed(_:)))
            copyItem.representedObject = displayPath
            pathMenu.addItem(copyItem)
            displayItem.submenu = pathMenu
        }
        menu.addItem(displayItem)
        return menu
    }

    private var finderEnabled: Bool {
        modeEnabled && NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "local.WindowsMacBridge" }
    }
    private func requestMode() {
        DistributedNotificationCenter.default().postNotificationName(FinderModeChannel.current.requestName,
            object: FinderModeChannel.requestObject, userInfo: nil, deliverImmediately: true)
    }
    @objc private func modeChanged(_ notification: Notification) {
        guard let value = FinderModeChannel.enabled(from: notification.object) else { return }
        modeEnabled = value
        FIFinderSyncController.default().directoryURLs = [] // Never monitor the whole filesystem for keyboard shortcuts.
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Menu actions consume the immutable path captured when this menu was constructed.
    @objc private func copyFolder(_ sender: Any?) { copy((sender as? NSMenuItem)?.representedObject as? String) }
    @objc private func copySelected(_ sender: Any?) { copy((sender as? NSMenuItem)?.representedObject as? String) }
    @objc private func copyDisplayed(_ sender: Any?) { copy((sender as? NSMenuItem)?.representedObject as? String) }
    private func copy(_ path: String?) {
        guard finderEnabled, let path else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(path, forType: .string)
    }
}
