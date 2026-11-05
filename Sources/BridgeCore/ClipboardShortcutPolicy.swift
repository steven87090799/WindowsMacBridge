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
            let canonical = ordinary.output.keyCode
            if canonical == 9, !finderMovePending { return ordinary }
            guard let finder = RuleEngine.finder.match(keyCode: canonical, modifiers: .control) else { return ordinary }
            return .init(id: finder.id, input: ordinary.input, output: finder.output, action: finder.action)
        }
        return ordinary
    }
    public static func isClipboardInput(key: UInt16, modifiers: Modifiers) -> Bool {
        modifiers == .control && [UInt16(8), 7, 9, 0, 114].contains(key) || key == 114 && modifiers == .shift
    }
}
