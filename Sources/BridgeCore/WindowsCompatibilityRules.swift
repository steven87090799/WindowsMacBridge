// Physical ANSI key positions, matching the supplied Karabiner profile.
// Tables are compiled once. Outputs are never fed back through rule matching.
public enum WindowsCompatibilityRules {
    public static let altF4 = ShortcutRule(id: "windows.altF4", input: .init(keyCode: 118, modifiers: .option),
                                           output: .init(keyCode: 13, modifiers: .command), action: .window(.close))
    public static let general: [ShortcutRule] = [
        ShortcutRule(id: "windows.copy", input: .init(keyCode: 8, modifiers: [.control]), output: .init(keyCode: 8, modifiers: [.command])), // #13
        ShortcutRule(id: "windows.paste", input: .init(keyCode: 9, modifiers: [.control]), output: .init(keyCode: 9, modifiers: [.command])), // #14
        ShortcutRule(id: "windows.cut", input: .init(keyCode: 7, modifiers: [.control]), output: .init(keyCode: 7, modifiers: [.command])), // #15
        ShortcutRule(id: "windows.selectAll", input: .init(keyCode: 0, modifiers: [.control]), output: .init(keyCode: 0, modifiers: [.command])), // #16
        ShortcutRule(id: "windows.undo", input: .init(keyCode: 6, modifiers: [.control]), output: .init(keyCode: 6, modifiers: [.command])), // #17
        ShortcutRule(id: "windows.redo", input: .init(keyCode: 16, modifiers: [.control]), output: .init(keyCode: 6, modifiers: [.command, .shift])), // #18
        ShortcutRule(id: "windows.save", input: .init(keyCode: 1, modifiers: [.control]), output: .init(keyCode: 1, modifiers: [.command])), // #19
        ShortcutRule(id: "karabiner.20", input: .init(keyCode: 1, modifiers: [.control, .shift]), output: .init(keyCode: 1, modifiers: [.command, .shift])), // #20
        ShortcutRule(id: "windows.find", input: .init(keyCode: 3, modifiers: [.control]), output: .init(keyCode: 3, modifiers: [.command])), // #21
        ShortcutRule(id: "windows.print", input: .init(keyCode: 35, modifiers: [.control]), output: .init(keyCode: 35, modifiers: [.command])), // #22
        ShortcutRule(id: "karabiner.23", input: .init(keyCode: 31, modifiers: [.control]), output: .init(keyCode: 31, modifiers: [.command])), // #23
        ShortcutRule(id: "karabiner.24", input: .init(keyCode: 45, modifiers: [.control]), output: .init(keyCode: 45, modifiers: [.command])), // #24
        ShortcutRule(id: "karabiner.25", input: .init(keyCode: 13, modifiers: [.control]), output: .init(keyCode: 13, modifiers: [.command])), // #25
        ShortcutRule(id: "karabiner.26", input: .init(keyCode: 13, modifiers: [.control, .shift]), output: .init(keyCode: 13, modifiers: [.command, .shift])), // #26
        ShortcutRule(id: "karabiner.27", input: .init(keyCode: 43, modifiers: [.control]), output: .init(keyCode: 43, modifiers: [.command])), // #27
        ShortcutRule(id: "karabiner.28", input: .init(keyCode: 24, modifiers: [.control]), output: .init(keyCode: 24, modifiers: [.command])), // #28
        ShortcutRule(id: "karabiner.29", input: .init(keyCode: 24, modifiers: [.control, .shift]), output: .init(keyCode: 24, modifiers: [.command, .shift])), // #29
        ShortcutRule(id: "karabiner.30", input: .init(keyCode: 27, modifiers: [.control]), output: .init(keyCode: 27, modifiers: [.command])), // #30
        ShortcutRule(id: "karabiner.31", input: .init(keyCode: 29, modifiers: [.control]), output: .init(keyCode: 29, modifiers: [.command])), // #31
        ShortcutRule(id: "karabiner.32", input: .init(keyCode: 123, modifiers: [.control]), output: .init(keyCode: 123, modifiers: [.option])), // #32
        ShortcutRule(id: "karabiner.33", input: .init(keyCode: 124, modifiers: [.control]), output: .init(keyCode: 124, modifiers: [.option])), // #33
        ShortcutRule(id: "karabiner.34", input: .init(keyCode: 123, modifiers: [.control, .shift]), output: .init(keyCode: 123, modifiers: [.option, .shift])), // #34
        ShortcutRule(id: "karabiner.35", input: .init(keyCode: 124, modifiers: [.control, .shift]), output: .init(keyCode: 124, modifiers: [.option, .shift])), // #35
        ShortcutRule(id: "karabiner.36", input: .init(keyCode: 115, modifiers: [.control]), output: .init(keyCode: 126, modifiers: [.command])), // #36
        ShortcutRule(id: "karabiner.37", input: .init(keyCode: 119, modifiers: [.control]), output: .init(keyCode: 125, modifiers: [.command])), // #37
        ShortcutRule(id: "karabiner.38", input: .init(keyCode: 115, modifiers: [.control, .shift]), output: .init(keyCode: 126, modifiers: [.command, .shift])), // #38
        ShortcutRule(id: "karabiner.39", input: .init(keyCode: 119, modifiers: [.control, .shift]), output: .init(keyCode: 125, modifiers: [.command, .shift])), // #39
        ShortcutRule(id: "karabiner.40", input: .init(keyCode: 51, modifiers: [.control]), output: .init(keyCode: 51, modifiers: [.option])), // #40
        ShortcutRule(id: "karabiner.41", input: .init(keyCode: 117, modifiers: [.control]), output: .init(keyCode: 117, modifiers: [.option])), // #41
    ]
    public static let browser: [ShortcutRule] = [
        ShortcutRule(id: "karabiner.42", input: .init(keyCode: 17, modifiers: [.control]), output: .init(keyCode: 17, modifiers: [.command])), // #42
        ShortcutRule(id: "karabiner.43", input: .init(keyCode: 17, modifiers: [.control, .shift]), output: .init(keyCode: 17, modifiers: [.command, .shift])), // #43
        ShortcutRule(id: "karabiner.44", input: .init(keyCode: 37, modifiers: [.control]), output: .init(keyCode: 37, modifiers: [.command])), // #44
        ShortcutRule(id: "karabiner.45", input: .init(keyCode: 15, modifiers: [.control]), output: .init(keyCode: 15, modifiers: [.command])), // #45
        ShortcutRule(id: "karabiner.46", input: .init(keyCode: 15, modifiers: [.control, .shift]), output: .init(keyCode: 15, modifiers: [.command, .shift])), // #46
        ShortcutRule(id: "karabiner.47", input: .init(keyCode: 2, modifiers: [.control]), output: .init(keyCode: 2, modifiers: [.command])), // #47
        ShortcutRule(id: "karabiner.48", input: .init(keyCode: 11, modifiers: [.control, .shift]), output: .init(keyCode: 11, modifiers: [.command, .shift])), // #48
        ShortcutRule(id: "karabiner.49", input: .init(keyCode: 45, modifiers: [.control, .shift]), output: .init(keyCode: 45, modifiers: [.command, .shift])), // #49
        ShortcutRule(id: "karabiner.50", input: .init(keyCode: 123, modifiers: [.option]), output: .init(keyCode: 33, modifiers: [.command])), // #50
        ShortcutRule(id: "karabiner.51", input: .init(keyCode: 124, modifiers: [.option]), output: .init(keyCode: 30, modifiers: [.command])), // #51
        ShortcutRule(id: "karabiner.52", input: .init(keyCode: 18, modifiers: [.control]), output: .init(keyCode: 18, modifiers: [.command])), // #52
        ShortcutRule(id: "karabiner.53", input: .init(keyCode: 19, modifiers: [.control]), output: .init(keyCode: 19, modifiers: [.command])), // #53
        ShortcutRule(id: "karabiner.54", input: .init(keyCode: 20, modifiers: [.control]), output: .init(keyCode: 20, modifiers: [.command])), // #54
        ShortcutRule(id: "karabiner.55", input: .init(keyCode: 21, modifiers: [.control]), output: .init(keyCode: 21, modifiers: [.command])), // #55
        ShortcutRule(id: "karabiner.56", input: .init(keyCode: 23, modifiers: [.control]), output: .init(keyCode: 23, modifiers: [.command])), // #56
        ShortcutRule(id: "karabiner.57", input: .init(keyCode: 22, modifiers: [.control]), output: .init(keyCode: 22, modifiers: [.command])), // #57
        ShortcutRule(id: "karabiner.58", input: .init(keyCode: 26, modifiers: [.control]), output: .init(keyCode: 26, modifiers: [.command])), // #58
        ShortcutRule(id: "karabiner.59", input: .init(keyCode: 28, modifiers: [.control]), output: .init(keyCode: 28, modifiers: [.command])), // #59
        ShortcutRule(id: "karabiner.60", input: .init(keyCode: 25, modifiers: [.control]), output: .init(keyCode: 25, modifiers: [.command])), // #60
    ]
    public static let finder: [ShortcutRule] = [
        ShortcutRule(id: "karabiner.61", input: .init(keyCode: 8, modifiers: [.control]), output: .init(keyCode: 8, modifiers: [.command]), action: .finder(.copy)), // #61
        ShortcutRule(id: "karabiner.62", input: .init(keyCode: 7, modifiers: [.control]), output: .init(keyCode: 8, modifiers: [.command]), action: .finder(.cut)), // #62
        ShortcutRule(id: "karabiner.64", input: .init(keyCode: 9, modifiers: [.control]), output: .init(keyCode: 9, modifiers: [.command]), action: .finder(.paste)), // #64
        ShortcutRule(id: "karabiner.65", input: .init(keyCode: 0, modifiers: [.control]), output: .init(keyCode: 0, modifiers: [.command])), // #65
        ShortcutRule(id: "karabiner.66", input: .init(keyCode: 6, modifiers: [.control]), output: .init(keyCode: 6, modifiers: [.command])), // #66
        ShortcutRule(id: "karabiner.67", input: .init(keyCode: 16, modifiers: [.control]), output: .init(keyCode: 6, modifiers: [.command, .shift])), // #67
        ShortcutRule(id: "karabiner.68", input: .init(keyCode: 45, modifiers: [.control]), output: .init(keyCode: 45, modifiers: [.command])), // #68
        ShortcutRule(id: "karabiner.69", input: .init(keyCode: 13, modifiers: [.control]), output: .init(keyCode: 13, modifiers: [.command])), // #69
        ShortcutRule(id: "karabiner.70", input: .init(keyCode: 45, modifiers: [.control, .shift]), output: .init(keyCode: 45, modifiers: [.command, .shift]), action: .finder(.newFolder)), // #70
        ShortcutRule(id: "karabiner.71", input: .init(keyCode: 37, modifiers: [.control]), output: .init(keyCode: 5, modifiers: [.command, .shift]), action: .finder(.goToFolder)), // #71
        ShortcutRule(id: "karabiner.72", input: .init(keyCode: 123, modifiers: [.option]), output: .init(keyCode: 33, modifiers: [.command])), // #72
        ShortcutRule(id: "karabiner.73", input: .init(keyCode: 124, modifiers: [.option]), output: .init(keyCode: 30, modifiers: [.command])), // #73
        ShortcutRule(id: "karabiner.74", input: .init(keyCode: 36, modifiers: []), output: .init(keyCode: 31, modifiers: [.command]), action: .finder(.open)), // #74
        ShortcutRule(id: "karabiner.75", input: .init(keyCode: 120, modifiers: []), output: .init(keyCode: 36, modifiers: []), action: .finder(.rename)), // #75
        ShortcutRule(id: "karabiner.76", input: .init(keyCode: 51, modifiers: [.fn]), output: .init(keyCode: 51, modifiers: [.command]), action: .finder(.trash)), // #76
    ]
    public static let finderExtras: [ShortcutRule] = [
        ShortcutRule(id: "finder.delete", input: .init(keyCode: 117, modifiers: []), output: .init(keyCode: 51, modifiers: [.command]), action: .finder(.trash)),
        ShortcutRule(id: "finder.permanentDelete", input: .init(keyCode: 117, modifiers: [.shift]), output: .init(keyCode: 51, modifiers: [.command, .option]), action: .finder(.permanentDelete)),
        ShortcutRule(id: "finder.parentFolder", input: .init(keyCode: 51, modifiers: []), output: .init(keyCode: 126, modifiers: [.command]), action: .finder(.parentFolder)),
    ]
    public static let textNavigation: [ShortcutRule] = [
        ShortcutRule(id: "text.home", input: .init(keyCode: 115, modifiers: []), output: .init(keyCode: 123, modifiers: .command)),
        ShortcutRule(id: "text.end", input: .init(keyCode: 119, modifiers: []), output: .init(keyCode: 124, modifiers: .command)),
        ShortcutRule(id: "text.selectHome", input: .init(keyCode: 115, modifiers: .shift), output: .init(keyCode: 123, modifiers: [.command, .shift])),
        ShortcutRule(id: "text.selectEnd", input: .init(keyCode: 119, modifiers: .shift), output: .init(keyCode: 124, modifiers: [.command, .shift])),
    ]
    public static let system: [ShortcutRule] = [
        ShortcutRule(id: "karabiner.11", input: .init(keyCode: 37, modifiers: [.option]), output: .init(keyCode: 12, modifiers: [.control, .command])), // #11
        ShortcutRule(id: "karabiner.12", input: .init(keyCode: 14, modifiers: [.option]), output: .init(keyCode: 14, modifiers: [.option]), action: .system(.openFinder)), // #12
        ShortcutRule(id: "karabiner.78", input: .init(keyCode: 53, modifiers: [.control, .shift]), output: .init(keyCode: 53, modifiers: [.control, .shift]), action: .system(.activityMonitor)), // #78
    ]
}
