/// `folder`: the AX walk positively reached a Finder window's file view with
/// no text field or sidebar in the focus chain, but nothing is selected (for
/// example an empty destination folder). `unknown` includes every AX failure.
public enum FinderFocus: Sendable { case files, folder, text, unknown }
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
