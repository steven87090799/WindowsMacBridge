import AppKit
import FinderSync

/// Finder supplies selected and targeted URLs only during menu construction/actions.
/// No background file scanning or pasteboard reads are needed.
final class FinderSync: FIFinderSync {
    private var currentKind: FIMenuKind = .contextualMenuForContainer
    private var modeEnabled = false
    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(modeChanged(_:)),
            name: FinderModeChannel.current.stateName, object: nil)
        requestMode()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self) }
    override func beginObservingDirectory(at url: URL) { requestMode() }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        requestMode()
        guard finderEnabled, menuKind != .toolbarItemMenu else { return nil }
        currentKind = menuKind
        let menu = NSMenu(title: "WindowsMacBridge")
        menu.autoenablesItems = false
        let folder = folderPath
        let selected = selectedURLs
        let folderItem = item("複製目前資料夾路徑", #selector(copyFolder(_:)))
        folderItem.isEnabled = folder != nil
        menu.addItem(folderItem)
        let selectedItem = item("複製選取項目完整路徑", #selector(copySelected(_:)))
        selectedItem.isEnabled = !selected.isEmpty
        menu.addItem(selectedItem)
        let displayPath = FinderPathSelection.displayed(selectedURLs: selected,
            targetedURL: FIFinderSyncController.default().targetedURL(),
            itemTarget: menuKind == .contextualMenuForItems)
        let displayItem = NSMenuItem(title: "顯示目前資料夾路徑", action: nil, keyEquivalent: "")
        displayItem.isEnabled = displayPath != nil
        if let displayPath {
            let pathMenu = NSMenu(title: "完整 POSIX 路徑")
            let pathItem = NSMenuItem(title: displayPath, action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            pathMenu.addItem(pathItem)
            pathMenu.addItem(item("複製此路徑", #selector(copyDisplayed(_:))))
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
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private var folderPath: String? {
        FinderPathSelection.folder(targetedURL: FIFinderSyncController.default().targetedURL(),
                                   itemTarget: currentKind == .contextualMenuForItems)
    }
    private var selectedURLs: [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    @objc private func copyFolder(_ sender: Any?) { copy(folderPath) }
    @objc private func copySelected(_ sender: Any?) {
        copy(FinderPathSelection.selected(selectedURLs))
    }
    @objc private func copyDisplayed(_ sender: Any?) {
        copy(FinderPathSelection.displayed(selectedURLs: selectedURLs,
            targetedURL: FIFinderSyncController.default().targetedURL(),
            itemTarget: currentKind == .contextualMenuForItems))
    }
    private func copy(_ path: String?) {
        guard let path else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(path, forType: .string)
    }
}
