/// Basic clipboard keys are independent of text composition and local App
/// profiles. Windows guests already understand raw Control and keep it.
public enum ClipboardShortcutPolicy {
    public static func match(key: UInt16, modifiers: Modifiers, context: ApplicationContext,
                             finderEnabled: Bool, finderMovePending: Bool = true) -> ShortcutRule? {
        guard context.mode != .remoteWindows, context.mode != .virtualMachine else { return nil }
        if context.mode == .terminal, modifiers == [.control, .shift], key == 8 {
            return RuleEngine.terminalClipboard.match(keyCode: key, modifiers: modifiers)
        }
        guard let ordinary = RuleEngine.clipboard.match(keyCode: key, modifiers: modifiers) else { return nil }
        if context.bundleID == "com.apple.finder", finderEnabled {
            if key == 9, !finderMovePending { return ordinary }
            return RuleEngine.finder.match(keyCode: key, modifiers: modifiers) ?? ordinary
        }
        return ordinary
    }
    public static func isClipboardInput(key: UInt16, modifiers: Modifiers) -> Bool {
        modifiers == .control && [UInt16(8), 7, 9, 0].contains(key)
    }
}
