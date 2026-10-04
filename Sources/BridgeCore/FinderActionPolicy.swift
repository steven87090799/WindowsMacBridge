/// Finder focus from positive AX evidence only (see FinderFocusReader).
/// - files: focus is inside a Finder file-content container with a selected file item.
/// - folder: focus is inside a file-content container with nothing selected (empty folder).
/// - text: a text field (rename, search, Go to Folder).
/// - sidebar, chrome: Finder UI that is not file content (sidebar; toolbar, sheet, dialog).
/// - unknown: AX failure, timeout or an incomplete/unrecognised hierarchy.
/// "Not text" never implies file content.
public enum FinderFocus: Sendable, Equatable { case files, folder, text, sidebar, chrome, unknown }
public enum FinderActionPolicy {
    /// An armed cut becomes a move only on positive file-view evidence. An AX
    /// timeout must never turn a text paste into a file move.
    public static func allowsMove(focus: FinderFocus) -> Bool { focus == .files || focus == .folder }
    /// Navigation and new-folder actions need a file view, not a selection.
    public static func inFileView(_ focus: FinderFocus) -> Bool { focus == .files || focus == .folder }
    public static func deleteOutput(focus: FinderFocus) -> Shortcut {
        focus == .files ? Shortcut(keyCode: 51, modifiers: .command) : Shortcut(keyCode: 117, modifiers: [])
    }
}
