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
    public static let windows = try! RuleEngine(rules: WindowsCompatibilityRules.general)
    public static let browser = try! RuleEngine(rules: WindowsCompatibilityRules.browser)
    public static let browserCommandAlt = try! RuleEngine(rules: WindowsCompatibilityRules.browserCommandAlt)
    public static let finder = try! RuleEngine(rules: WindowsCompatibilityRules.finder)
    public static let finderCommandAlt = try! RuleEngine(rules: WindowsCompatibilityRules.finderCommandAlt)
    public static let finderExtras = try! RuleEngine(rules: WindowsCompatibilityRules.finderExtras)
    public static let system = try! RuleEngine(rules: WindowsCompatibilityRules.system)
    public static let systemCommand = try! RuleEngine(rules: WindowsCompatibilityRules.systemCommand)
    public static let systemExtras = try! RuleEngine(rules: WindowsCompatibilityRules.systemExtras)
    public static let systemExtrasCommand = try! RuleEngine(rules: WindowsCompatibilityRules.systemExtrasCommand)
    public static let textNavigation = try! RuleEngine(rules: WindowsCompatibilityRules.textNavigation)
}
