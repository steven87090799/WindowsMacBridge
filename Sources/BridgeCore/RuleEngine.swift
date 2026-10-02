public enum RuleCompilationError: Error, Equatable {
    case duplicateShortcut
    case invalidKeyCode
    case unsupportedModifier
}

/// Immutable, bounded table: exact modifiers only. Caps Lock is excluded by the adapter.
public struct RuleEngine: Sendable {
    // Most of the 4,096 slots are empty. Store a compact index instead of a
    // full optional rule (strings, chords and action payload) in every slot.
    private let table: [UInt16]
    private let rules: [ShortcutRule]
    public init(rules: [ShortcutRule]) throws {
        var result = [UInt16](repeating: 0, count: 128 * 32)
        for (ruleIndex, rule) in rules.enumerated() {
            guard rule.input.keyCode < 128, rule.output.keyCode < 128 else {
                throw RuleCompilationError.invalidKeyCode
            }
            guard rule.input.modifiers.rawValue < 32, rule.output.modifiers.rawValue < 32 else {
                throw RuleCompilationError.unsupportedModifier
            }
            let index = Int(rule.input.modifiers.rawValue) * 128 + Int(rule.input.keyCode)
            guard result[index] == 0 else { throw RuleCompilationError.duplicateShortcut }
            // At most 4,096 distinct validated chords can reach this point.
            result[index] = UInt16(ruleIndex + 1)
        }
        table = result
        self.rules = rules
    }
    public func match(keyCode: UInt16, modifiers: Modifiers) -> ShortcutRule? {
        guard keyCode < 128, modifiers.rawValue < 32 else { return nil }
        let index = table[Int(modifiers.rawValue) * 128 + Int(keyCode)]
        return index == 0 ? nil : rules[Int(index) - 1]
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
