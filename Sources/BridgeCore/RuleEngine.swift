public enum RuleCompilationError: Error, Equatable {
    case duplicateShortcut
    case invalidKeyCode
    case unsupportedModifier
}

/// Immutable, bounded table: exact modifiers only. Caps Lock is excluded by the adapter.
public struct RuleEngine: Sendable {
    private let table: [ShortcutRule?]
    public init(rules: [ShortcutRule]) throws {
        var result = [ShortcutRule?](repeating: nil, count: 128 * 32)
        for rule in rules {
            guard rule.input.keyCode < 128, rule.output.keyCode < 128 else {
                throw RuleCompilationError.invalidKeyCode
            }
            guard rule.input.modifiers.rawValue < 32, rule.output.modifiers.rawValue < 32 else {
                throw RuleCompilationError.unsupportedModifier
            }
            let index = Int(rule.input.modifiers.rawValue) * 128 + Int(rule.input.keyCode)
            guard result[index] == nil else { throw RuleCompilationError.duplicateShortcut }
            result[index] = rule
        }
        table = result
    }
    public func match(keyCode: UInt16, modifiers: Modifiers) -> ShortcutRule? {
        guard keyCode < 128, modifiers.rawValue < 32 else { return nil }
        return table[Int(modifiers.rawValue) * 128 + Int(keyCode)]
    }
    // ANSI virtual key positions. The platform enables these only for verified US/ABC layouts.
    public static let windows = try! RuleEngine(rules: [
        ("copy", UInt16(8)), ("cut", 7), ("paste", 9), ("selectAll", 0),
        ("undo", 6), ("save", 1), ("find", 3), ("print", 35)
    ].map { id, key in
        ShortcutRule(id: "windows.\(id)", input: .init(keyCode: key, modifiers: .control),
                     output: .init(keyCode: key, modifiers: .command))
    } + [ShortcutRule(id: "windows.redo", input: .init(keyCode: 16, modifiers: .control),
                       output: .init(keyCode: 6, modifiers: [.command, .shift]))])
}
