import ApplicationServices
import Testing
import BridgeCore
@testable import BridgePlatform

/// AX hierarchy fixtures, focused element first and window last, as the reader collects them.
struct FinderFocusReaderTests {
    private typealias Node = FinderAXNode
    private static let window = Node(role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
    private static let split = Node(role: kAXSplitGroupRole)
    private static let scroll = Node(role: kAXScrollAreaRole)
    private func classify(_ chain: [Node], complete: Bool = true) -> FinderFocus {
        FinderFocusReader.classify(chain, complete: complete)
    }

    @Test func fileListAndGridWithASelectedFileAreFiles() {
        for role in [kAXOutlineRole, kAXTableRole, kAXListRole] {
            let content = Node(role: role, selectedFileURL: true)
            #expect(classify([content, Self.scroll, Self.split, Self.window]) == .files)
            // Focus on the selected row/cell inside the container.
            #expect(classify([Node(role: kAXRowRole), content, Self.scroll, Self.split, Self.window]) == .files)
        }
        #expect(classify([Node(role: kAXBrowserRole, selectedFileURL: true), Self.split, Self.window]) == .files)
    }
    @Test func emptyFolderContentIsFolderNotFiles() {
        #expect(classify([Node(role: kAXOutlineRole), Self.scroll, Self.split, Self.window]) == .folder)
        #expect(classify([Node(role: kAXListRole), Self.scroll, Self.window]) == .folder)
    }
    @Test func searchRenameAndGoToFieldsAreText() {
        let search = Node(role: kAXTextFieldRole, subrole: kAXSearchFieldSubrole)
        #expect(classify([search, Node(role: kAXToolbarRole), Self.window]) == .text)
        // Rename field inside a selected row of the file list.
        let rename = Node(role: kAXTextFieldRole)
        #expect(classify([rename, Node(role: kAXRowRole), Node(role: kAXOutlineRole, selectedFileURL: true), Self.scroll, Self.window]) == .text)
        // Text wins even if the walk could not finish.
        #expect(classify([Node(role: kAXTextAreaRole)], complete: false) == .text)
    }
    @Test func sidebarIsNeverFileContentEvenWithASelectedURL() {
        let byIdentifier = Node(role: kAXOutlineRole, identifier: "FinderSidebar", selectedFileURL: true)
        let byDescription = Node(role: kAXOutlineRole, description: "Sidebar", selectedFileURL: true)
        let sourceList = Node(role: kAXOutlineRole, subrole: "AXSourceList", selectedFileURL: true)
        for sidebar in [byIdentifier, byDescription, sourceList] {
            #expect(classify([Node(role: kAXRowRole), sidebar, Self.scroll, Self.split, Self.window]) == .sidebar)
        }
    }
    @Test func toolbarSheetAndDialogAreChrome() {
        #expect(classify([Node(role: kAXButtonRole), Node(role: kAXToolbarRole), Self.window]) == .chrome)
        // A sheet over a file list must not inherit the file selection.
        #expect(classify([Node(role: kAXButtonRole), Node(role: kAXSheetRole), Node(role: kAXOutlineRole, selectedFileURL: true), Self.window]) == .chrome)
        let dialog = Node(role: kAXWindowRole, subrole: kAXDialogSubrole)
        #expect(classify([Node(role: kAXButtonRole), dialog]) == .chrome)
        #expect(classify([Node(role: kAXOutlineRole, selectedFileURL: true), Self.scroll, Node(role: kAXWindowRole, subrole: kAXSystemDialogSubrole)]) == .chrome)
    }
    @Test func windowAncestorAloneIsNotFileContentEvidence() {
        // Old model: reaching AXWindow without text/sidebar meant "folder".
        #expect(classify([Node(role: kAXButtonRole), Self.split, Self.window]) == .unknown)
        #expect(classify([Node(role: kAXGroupRole), Self.window]) == .unknown)
        #expect(classify([Self.window]) == .unknown)
        // A content role without the scroll-area structure is not trusted either.
        #expect(classify([Node(role: kAXListRole, selectedFileURL: true), Self.window]) == .unknown)
    }
    @Test func axTimeoutFailureAndIncompleteHierarchiesAreUnknown() {
        let content = Node(role: kAXOutlineRole, selectedFileURL: true)
        #expect(classify([content, Self.scroll], complete: false) == .unknown)   // timeout / parent failure
        #expect(classify([], complete: false) == .unknown)                       // focused element unreadable
        #expect(classify([content, Self.scroll, Self.split]) == .unknown)        // never reached a window
    }
    @Test func destructiveActionsRequirePositiveEvidence() {
        // Delete (trash), rename and permanent delete use .files only; move/new/parent need file content.
        #expect(FinderActionPolicy.deleteOutput(focus: .files).modifiers == .command)
        for focus: FinderFocus in [.folder, .text, .sidebar, .chrome, .unknown] {
            #expect(FinderActionPolicy.deleteOutput(focus: focus).modifiers.isEmpty)
        }
        #expect(!FinderActionPolicy.allowsMove(focus: .unknown))
    }
}
