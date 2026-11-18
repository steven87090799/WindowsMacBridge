/// Additions to the original, independently tested Karabiner compatibility fixture.
public enum WindowsShortcutExtensions {
    private static func rule(_ id: String, _ key: UInt16, _ input: Modifiers,
                             _ outputKey: UInt16, _ output: Modifiers) -> ShortcutRule {
        .init(id: id, input: .init(keyCode: key, modifiers: input),
              output: .init(keyCode: outputKey, modifiers: output))
    }
    public static let clipboardAliases = [
        rule("windows.copyInsert", 114, .control, 8, .command),
        rule("windows.pasteInsert", 114, .shift, 9, .command)
    ]
    public static let general = [
        rule("windows.bold", 11, .control, 11, .command),
        rule("windows.italic", 34, .control, 34, .command),
        rule("windows.underline", 32, .control, 32, .command),
        rule("windows.redoShiftZ", 6, [.control, .shift], 6, [.command, .shift]),
        rule("windows.pastePlain", 9, [.control, .shift], 9, [.command, .option, .shift]),
        rule("windows.replace", 4, .control, 3, [.command, .option]),
        rule("windows.closeDocument", 118, .control, 13, .command)
    ]
    public static let paragraphs = [
        rule("text.paragraphUp", 126, .control, 126, .option),
        rule("text.paragraphDown", 125, .control, 125, .option),
        rule("text.selectParagraphUp", 126, [.control, .shift], 126, [.option, .shift]),
        rule("text.selectParagraphDown", 125, [.control, .shift], 125, [.option, .shift])
    ]
    public static let finder = [
        rule("finder.find", 3, .control, 3, .command),
        rule("finder.search", 14, .control, 3, .command),
        rule("finder.newTab", 17, .control, 17, .command),
        rule("finder.closeTab", 118, .control, 13, .command),
        rule("finder.getInfo", 36, .command, 34, .command),
        rule("finder.redoShiftZ", 6, [.control, .shift], 6, [.command, .shift]),
        ShortcutRule(id: "finder.addressBar", input: .init(keyCode: 2, modifiers: .command),
            output: .init(keyCode: 5, modifiers: [.command, .shift]), action: .finder(.goToFolder))
    ]
    private static let browserCommon = [
        rule("browser.findNext", 5, .control, 5, .command),
        rule("browser.findPrevious", 5, [.control, .shift], 5, [.command, .shift]),
        rule("browser.addressAltD", 2, .command, 37, .command),
        rule("browser.searchCtrlK", 40, .control, 37, .command),
        rule("browser.searchCtrlE", 14, .control, 37, .command),
        rule("browser.reloadF5", 96, [], 15, .command),
        rule("browser.findF3", 99, [], 5, .command),
        rule("browser.findPreviousF3", 99, .shift, 5, [.command, .shift]),
        rule("browser.fullScreenF11", 103, [], 3, [.control, .command])
    ]
    private static let chromium = [
        rule("browser.history", 4, .control, 16, .command),
        rule("browser.downloads", 38, .control, 38, [.command, .shift]),
        rule("browser.pastePlain", 9, [.control, .shift], 9, [.command, .shift]),
        rule("browser.bookmarkAll", 2, [.control, .shift], 2, [.command, .shift]),
        rule("browser.bookmarkManager", 31, [.control, .shift], 11, [.command, .option]),
        rule("browser.viewSource", 32, .control, 32, [.command, .option]),
        rule("browser.clearData", 117, [.control, .shift], 51, [.command, .shift]),
        rule("browser.console", 38, [.control, .shift], 38, [.command, .option]),
        rule("browser.devTools", 34, [.control, .shift], 34, [.command, .option]),
        rule("browser.devToolsF12", 111, [], 34, [.command, .option]),
        rule("browser.reloadIgnoringCache", 96, .shift, 15, [.command, .shift]),
        rule("browser.homePage", 115, .command, 4, [.command, .shift])
    ]
    private static let firefox = [
        rule("browser.history", 4, .control, 4, [.command, .shift]),
        rule("browser.downloads", 38, .control, 38, .command),
        rule("browser.pastePlain", 9, [.control, .shift], 9, [.command, .shift]),
        rule("browser.viewSource", 32, .control, 32, .command),
        rule("browser.reloadIgnoringCache", 96, .control, 15, [.command, .shift]),
        rule("browser.fullScreenF11", 103, [], 3, [.command, .shift]),
        rule("browser.searchCtrlK", 40, .control, 40, .command),
        rule("browser.searchCtrlE", 14, .control, 40, .command),
        rule("browser.homePage", 115, .command, 115, .option),
        rule("browser.bookmarkAll", 2, [.control, .shift], 2, [.command, .shift]),
        rule("browser.bookmarkManager", 31, [.control, .shift], 31, [.command, .shift]),
        rule("browser.clearData", 117, [.control, .shift], 51, [.command, .shift]),
        rule("browser.devTools", 34, [.control, .shift], 34, [.command, .option]),
        rule("browser.webConsole", 40, [.control, .shift], 40, [.command, .option]),
        rule("browser.console", 38, [.control, .shift], 38, [.command, .shift]),
        rule("browser.inspector", 8, [.control, .shift], 8, [.command, .option])
    ]
    /// Chromium-based browsers can assign different native commands to the same
    /// Windows input. Resolve those differences once when compiling the tables.
    private static func overriding(_ base: [ShortcutRule], with overrides: [ShortcutRule]) -> [ShortcutRule] {
        let inputs = Set(overrides.map(\.input))
        return base.filter { !inputs.contains($0.input) } + overrides
    }
    private static let edge = overriding(chromium, with: [
        rule("browser.downloads", 38, .control, 37, [.command, .option])
    ])
    private static let opera = overriding(chromium, with: [
        rule("browser.history", 4, .control, 4, [.command, .shift]),
        rule("browser.downloads", 38, .control, 38, .command),
        rule("browser.viewSource", 32, .control, 32, .command)
    ])
    private static let vivaldi = overriding(chromium, with: [
        rule("browser.downloadsPanel", 2, [.control, .shift], 37, [.command, .option])
    ])
    private static let safari = [
        rule("browser.history", 4, .control, 16, .command),
        rule("browser.downloads", 38, .control, 37, [.command, .option]),
        rule("browser.reloadIgnoringCacheCtrlR", 15, [.control, .shift], 15, [.command, .option]),
        rule("browser.reloadIgnoringCache", 96, .shift, 15, [.command, .option])
    ]
    public static let browserKeys = Set((browserCommon + chromium + firefox + safari + edge + opera + vivaldi).map { $0.input.keyCode })
    private static let generalTable = try! RuleEngine(rules: general)
    private static let finderTable = try! RuleEngine(rules: finder)
    private static let commonTable = try! RuleEngine(rules: browserCommon)
    private static let chromiumTable = try! RuleEngine(rules: chromium)
    private static let firefoxTable = try! RuleEngine(rules: firefox)
    private static let safariTable = try! RuleEngine(rules: safari)
    private static let edgeTable = try! RuleEngine(rules: edge)
    private static let operaTable = try! RuleEngine(rules: opera)
    private static let vivaldiTable = try! RuleEngine(rules: vivaldi)

    public static func prepare() {
        _ = generalTable; _ = finderTable; _ = commonTable
        _ = chromiumTable; _ = firefoxTable; _ = safariTable
        _ = edgeTable; _ = operaTable; _ = vivaldiTable
    }
    public static func generalRule(key: UInt16, modifiers: Modifiers, context: ApplicationContext) -> ShortcutRule? {
        if context.mode == .terminal {
            // Ctrl+B/I/H/G are shell commands, not text-formatting commands.
            return key == 9 && modifiers == [.control, .shift] ?
                rule("terminal.pastePlain", key, modifiers, 9, .command) : nil
        }
        if context.mode == .ide {
            if key == 9, modifiers == [.control, .shift] {
                return rule("ide.shiftPaste", key, modifiers, 9, [.command, .shift])
            }
        }
        return generalTable.match(keyCode: key, modifiers: modifiers)
    }
    public static func finderRule(key: UInt16, modifiers: Modifiers) -> ShortcutRule? {
        finderTable.match(keyCode: key, modifiers: modifiers)
    }
    public static func browserRule(key: UInt16, modifiers: Modifiers, context: ApplicationContext) -> ShortcutRule? {
        guard context.isBrowser else { return nil }
        let family: RuleEngine?
        switch context.bundleID {
        case let id where id.hasPrefix("org.mozilla.firefox"): family = firefoxTable
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview": family = safariTable
        case "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary":
            family = edgeTable
        case "com.operasoftware.Opera": family = operaTable
        case "com.vivaldi.Vivaldi": family = vivaldiTable
        case "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "company.thebrowser.Browser":
            family = chromiumTable
        default: family = nil
        }
        return family?.match(keyCode: key, modifiers: modifiers) ?? commonTable.match(keyCode: key, modifiers: modifiers)
    }
}

public enum TextNavigationAction: String, CaseIterable, Sendable {
    case home, end, selectHome, selectEnd, paragraphUp, paragraphDown, selectParagraphUp, selectParagraphDown
    case documentHome, documentEnd, selectDocumentHome, selectDocumentEnd

    public var ruleID: String {
        switch self {
        case .home: "text.contextual.home"
        case .end: "text.contextual.end"
        case .selectHome: "text.contextual.selectHome"
        case .selectEnd: "text.contextual.selectEnd"
        case .paragraphUp: "text.contextual.paragraphUp"
        case .paragraphDown: "text.contextual.paragraphDown"
        case .selectParagraphUp: "text.contextual.selectParagraphUp"
        case .selectParagraphDown: "text.contextual.selectParagraphDown"
        case .documentHome: "text.contextual.documentHome"
        case .documentEnd: "text.contextual.documentEnd"
        case .selectDocumentHome: "text.contextual.selectDocumentHome"
        case .selectDocumentEnd: "text.contextual.selectDocumentEnd"
        }
    }

    public func output(textFocused: Bool) -> Shortcut? {
        let select = self == .selectHome || self == .selectEnd || self == .selectParagraphUp || self == .selectParagraphDown ||
            self == .selectDocumentHome || self == .selectDocumentEnd
        let shift: Modifiers = select ? .shift : []
        switch self {
        case .home, .selectHome:
            return .init(keyCode: textFocused ? 123 : 115, modifiers: textFocused ? shift.union(.command) : shift)
        case .end, .selectEnd:
            return .init(keyCode: textFocused ? 124 : 119, modifiers: textFocused ? shift.union(.command) : shift)
        case .documentHome, .selectDocumentHome:
            return .init(keyCode: textFocused ? 126 : 115, modifiers: textFocused ? shift.union(.command) : shift)
        case .documentEnd, .selectDocumentEnd:
            return .init(keyCode: textFocused ? 125 : 119, modifiers: textFocused ? shift.union(.command) : shift)
        case .paragraphUp, .selectParagraphUp:
            return textFocused ? .init(keyCode: 126, modifiers: shift.union(.option)) : nil
        case .paragraphDown, .selectParagraphDown:
            return textFocused ? .init(keyCode: 125, modifiers: shift.union(.option)) : nil
        }
    }
}

public enum TextNavigationPolicy {
    public static func match(key: UInt16, modifiers: Modifiers, context: ApplicationContext) -> ShortcutRule? {
        let finderDocument = context.bundleID == "com.apple.finder" && (key == 115 || key == 119) &&
            modifiers.subtracting(.shift) == .control
        guard let ordinary = finderDocument ? RuleEngine.windows.match(keyCode: key, modifiers: modifiers) :
            RuleEngine.textNavigation.match(keyCode: key, modifiers: modifiers) else { return nil }
        // Option+Up/Down moves source lines in several IDEs. Never treat an
        // editor or shell's native Ctrl+Up/Down bindings as Cocoa paragraphs.
        if (key == 125 || key == 126), context.mode == .ide || context.mode == .terminal { return nil }
        guard context.isBrowser || context.bundleID == "com.apple.finder" else { return ordinary }
        let action: TextNavigationAction
        switch (key, modifiers.contains(.shift)) {
        case (115, false): action = finderDocument ? .documentHome : .home
        case (115, true): action = finderDocument ? .selectDocumentHome : .selectHome
        case (119, false): action = finderDocument ? .documentEnd : .end
        case (119, true): action = finderDocument ? .selectDocumentEnd : .selectEnd
        case (126, false): action = .paragraphUp
        case (126, true): action = .selectParagraphUp
        case (125, false): action = .paragraphDown
        default: action = .selectParagraphDown
        }
        return .init(id: action.ruleID, input: ordinary.input,
            output: ordinary.output, action: .textNavigation(action))
    }
}
