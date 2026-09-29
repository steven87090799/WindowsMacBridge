import AppKit
import FinderSync

/// Finder supplies selected and targeted URLs only during menu construction/actions.
/// No background file scanning or pasteboard reads are needed.
final class FinderSync: FIFinderSync {
    private var currentKind: FIMenuKind = .contextualMenuForContainer
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
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
        let displayItem = item("顯示目前資料夾路徑", #selector(showPath(_:)))
        displayItem.isEnabled = folder != nil || !selected.isEmpty
        menu.addItem(displayItem)
        return menu
    }

    private var finderEnabled: Bool {
        UserDefaults(suiteName: "group.local.WindowsMacBridge")?.bool(forKey: "finder.enabled") ?? false
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
    @objc private func showPath(_ sender: Any?) {
        guard let path = FinderPathSelection.displayed(selectedURLs: selectedURLs,
                                                       targetedURL: FIFinderSyncController.default().targetedURL(),
                                                       itemTarget: currentKind == .contextualMenuForItems) else { return }
        let alert = NSAlert()
        alert.messageText = "完整 POSIX 路徑"
        alert.informativeText = path
        alert.addButton(withTitle: "複製")
        alert.addButton(withTitle: "關閉")
        if alert.runModal() == .alertFirstButtonReturn { copy(path) }
    }
    private func copy(_ path: String?) {
        guard let path else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(path, forType: .string)
    }
}
