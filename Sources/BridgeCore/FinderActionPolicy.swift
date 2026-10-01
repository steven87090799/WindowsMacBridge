public enum FinderFocus: Sendable { case files, text, unknown }
public enum FinderActionPolicy {
    public static func deleteOutput(focus: FinderFocus) -> Shortcut {
        focus == .files ? Shortcut(keyCode: 51, modifiers: .command) : Shortcut(keyCode: 117, modifiers: [])
    }
}
