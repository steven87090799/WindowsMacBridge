/// Input-thread confined in production; a deterministic value type in tests.
/// No synthetic modifier ownership exists in this first release.
public struct KeyboardEventProcessor: Sendable {
    private struct Press: Sendable {
        var rule: ShortcutRule?
        var contextPID: Int32
        var contextBundle: String
        var contextMode: ApplicationMode
        var suppress: Bool
        var repeatSuppressed = false
        var outputModifiers: Modifiers = []
        var releaseDrained = false
    }
    private var presses = [Press?](repeating: nil, count: 128)
    private var context = ApplicationContext()
    private var enabled = false
    private var layoutSupported = false
    private var controlsEnabled = true
    private var finderEnabled = false
    private var finderPermanentDeleteEnabled = false
    private var textNavigationEnabled = true
    private var altF4Enabled = false
    private var windowsKeyModifier: WindowsKeyModifier = .option
    private var winRunEnabled = false
    private var winSettingsEnabled = false
    private var winTaskViewEnabled = false
    private var nativeAppSwitchEnabled = false
    private var screenshotEnabled = false
    private var printScreen: PrintScreenBehavior = .snipping
    public private(set) var manualPassThrough = false
    private var awaitingNeutral = true
    private var pressCount = 0
    public private(set) var modifiers = ModifierStateMachine()
    public private(set) var processedCount: UInt64 = 0
    public private(set) var translatedCount: UInt64 = 0
    public private(set) var rules = RuleEngine.windows
    public var activePressCount: Int { pressCount }
    public var isAwaitingNeutral: Bool { awaitingNeutral }
    public init() {}

    public mutating func configure(context newContext: ApplicationContext, enabled: Bool,
                                   layoutSupported: Bool, controlsEnabled: Bool = true,
                                   finderEnabled: Bool = false,
                                   finderPermanentDeleteEnabled: Bool = false,
                                   textNavigationEnabled: Bool = true,
                                   altF4Enabled: Bool = false,
                                   windowsKeyModifier: WindowsKeyModifier = .option,
                                   winRunEnabled: Bool = false,
                                   winSettingsEnabled: Bool = false,
                                   winTaskViewEnabled: Bool = false,
                                   nativeAppSwitchEnabled: Bool = false,
                                   screenshotEnabled: Bool = false,
                                   printScreen: PrintScreenBehavior = .snipping) {
        let changedContext = context.processID != newContext.processID ||
            context.bundleID != newContext.bundleID || context.mode != newContext.mode ||
            context.isBrowser != newContext.isBrowser
        if changedContext {
            // Once a focus transaction ends, returning to the same PID must not revive it.
            for i in presses.indices where presses[i]?.rule != nil { presses[i]?.suppress = true }
        }
        if changedContext || self.enabled != enabled || self.layoutSupported != layoutSupported ||
            self.finderEnabled != finderEnabled ||
            self.finderPermanentDeleteEnabled != finderPermanentDeleteEnabled ||
            self.textNavigationEnabled != textNavigationEnabled || self.altF4Enabled != altF4Enabled ||
            self.windowsKeyModifier != windowsKeyModifier ||
            self.winRunEnabled != winRunEnabled || self.winSettingsEnabled != winSettingsEnabled ||
            self.winTaskViewEnabled != winTaskViewEnabled || self.nativeAppSwitchEnabled != nativeAppSwitchEnabled ||
            self.screenshotEnabled != screenshotEnabled || self.printScreen != printScreen {
            awaitingNeutral = true
        }
        context = newContext; self.enabled = enabled; self.layoutSupported = layoutSupported
        self.controlsEnabled = controlsEnabled; self.finderEnabled = finderEnabled
        self.finderPermanentDeleteEnabled = finderPermanentDeleteEnabled
        self.textNavigationEnabled = textNavigationEnabled; self.altF4Enabled = altF4Enabled
        self.windowsKeyModifier = windowsKeyModifier
        self.winRunEnabled = winRunEnabled; self.winSettingsEnabled = winSettingsEnabled
        self.winTaskViewEnabled = winTaskViewEnabled
        self.nativeAppSwitchEnabled = nativeAppSwitchEnabled
        self.screenshotEnabled = screenshotEnabled; self.printScreen = printScreen
    }

    public mutating func resumeManualPassThrough() { manualPassThrough = false; invalidate() }
    /// If the bounded action mailbox rejects a down, preserve its original down/up pair.
    public mutating func rejectAction(keyCode: UInt16) {
        guard keyCode < 128, presses[Int(keyCode)]?.rule?.action != nil else { return }
        presses[Int(keyCode)]?.rule = nil
        presses[Int(keyCode)]?.suppress = false
    }
    /// Called on the input thread before policy changes. Retain tombstones so physical
    /// repeat/up cannot generate a second release or resurrect the old shortcut.
    public mutating func drainTranslatedReleases(_ release: (UInt16, Modifiers, Int32) -> Void) {
        for i in presses.indices {
            guard let press = presses[i], let rule = press.rule, rule.action == nil, !press.releaseDrained else { continue }
            presses[i]?.releaseDrained = true; presses[i]?.suppress = true
            release(rule.output.keyCode, press.outputModifiers, press.contextPID)
        }
    }

    /// A gap makes retained presses tombstones, swallowing their later repeat/up.
    public mutating func invalidate() {
        awaitingNeutral = true
        modifiers.invalidate()
        for i in presses.indices where presses[i]?.rule != nil {
            presses[i]?.suppress = true
        }
    }

    /// Called outside the callback after a HID state probe finds every supported key released.
    public mutating func reconcileNeutralHardware() {
        for i in presses.indices { presses[i] = nil }
        pressCount = 0
        modifiers.reset(); awaitingNeutral = false
    }

    public mutating func reconcileIndependentSourceFlags(_ value: Modifiers) {
        modifiers.synchronizeAggregate(value.subtracting(.fn))
        for i in presses.indices {
            if let rule = presses[i]?.rule, !value.isSuperset(of: rule.input.modifiers) {
                presses[i]?.repeatSuppressed = true
            }
        }
        if value.isEmpty && pressCount == 0 { awaitingNeutral = false }
    }

    public mutating func process(_ event: KeyboardEvent) -> EventDecision {
        if event.isOwnEvent { return .passThrough }
        processedCount &+= 1
        if event.phase == .flagsChanged {
            if let side = event.modifierSide, let down = event.modifierDown {
                modifiers.observe(side, down: down, aggregate: event.modifiers)
            }
            // End repeats as soon as any trigger modifier is released. A later modifier
            // press must not revive the held shortcut; retain its translated key-up pair.
            for index in presses.indices {
                if let rule = presses[index]?.rule,
                   !event.modifiers.isSuperset(of: rule.input.modifiers) {
                    presses[index]?.repeatSuppressed = true
                }
            }
            if event.modifiers.isEmpty && activePressCount == 0 {
                modifiers.reset(); awaitingNeutral = false
            }
            return .passThrough
        }
        guard event.keyCode < 128 else { return .passThrough }
        let index = Int(event.keyCode)

        // Pairing takes precedence over new policy decisions, including pause.
        if let press = presses[index] {
            if event.phase == .up { presses[index] = nil; pressCount -= 1 }
            if press.suppress { return .suppress }
            guard let rule = press.rule else { return .passThrough }
            if press.contextPID != context.processID || press.contextBundle != context.bundleID ||
                press.contextMode != context.mode {
                // Never replay an old local chord into the newly focused remote/client app.
                return .suppress
            }
            // A repeat is stopped during pause/recovery. Release still pairs with its down.
            if event.phase == .down {
                // Event flags also catch a missing flagsChanged release.
                if !event.modifiers.isSuperset(of: rule.input.modifiers) {
                    presses[index]?.repeatSuppressed = true
                    return .suppress
                }
                if press.repeatSuppressed || !enabled || !layoutSupported || manualPassThrough { return .suppress }
            }
            return rewrite(event, rule: rule)
        }
        guard event.phase == .down else { return .passThrough }
        if event.isRepeat { return .passThrough }

        // Flags and side history are independent evidence. A missed flagsChanged event
        // must not silently enable a translation on an untrusted physical state.
        if event.modifiers.subtracting(.fn) != modifiers.aggregate {
            modifiers.invalidate()
        }

        // Reserved emergency pause, even in a protected application. Never consumes modifiers.
        if controlsEnabled && event.keyCode == 35 && event.modifiers == [.control, .option, .command] {
            presses[index] = Press(rule: nil, contextPID: context.processID,
                                   contextBundle: context.bundleID, contextMode: context.mode, suppress: true)
            pressCount += 1
            enabled = false; awaitingNeutral = true
            return .emergencyPause
        }
        // Reserved in all application profiles, like rule #1 in the supplied file.
        if controlsEnabled && modifiers.synchronized && event.keyCode == 35 && event.modifiers == .option &&
            modifiers.isDown(.rightOption) && !modifiers.isDown(.leftOption) {
            presses[index] = Press(rule: nil, contextPID: context.processID,
                                   contextBundle: context.bundleID, contextMode: context.mode, suppress: true)
            pressCount += 1
            manualPassThrough.toggle(); invalidate()
            return .togglePassThrough
        }
        if event.modifiers.isEmpty && activePressCount == 0 { awaitingNeutral = false }

        let rule = event.allowsTranslation && enabled && layoutSupported && !manualPassThrough && !awaitingNeutral && modifiers.synchronized
            ? match(event) : nil
        presses[index] = Press(rule: rule, contextPID: context.processID,
                               contextBundle: context.bundleID, contextMode: context.mode, suppress: false)
        pressCount += 1
        guard let rule else { return .passThrough }
        if case .rewrite(_, let flags, _) = rewrite(event, rule: rule) { presses[index]?.outputModifiers = flags }
        translatedCount &+= 1
        if let action = rule.action {
            presses[index]?.suppress = true
            return .action(action, ruleID: rule.id)
        }
        return rewrite(event, rule: rule)
    }

    private func match(_ event: KeyboardEvent) -> ShortcutRule? {
        // Remote/VM/game protections precede every local action, not only Ctrl shortcuts.
        guard context.mode == .macOS else { return nil }
        if nativeAppSwitchEnabled && event.keyCode == 48 && event.modifiers.subtracting(.shift) == windowsKeyModifier.altFlag {
            return ShortcutRule(id: "windows.nativeAppSwitch", input: .init(keyCode: 48, modifiers: event.modifiers),
                                output: .init(keyCode: 48, modifiers: Modifiers.command.union(event.modifiers.intersection(.shift))))
        }
        if screenshotEnabled, let kind = WindowsScreenshotShortcuts.match(key: event.keyCode, modifiers: event.modifiers,
                                                                         windowsKey: windowsKeyModifier, printScreen: printScreen) {
            return ShortcutRule(id: "windows.screenshot", input: .init(keyCode: event.keyCode, modifiers: event.modifiers),
                                output: .init(keyCode: event.keyCode, modifiers: []), action: .screenshot(kind))
        }
        let systemRules = windowsKeyModifier == .option ? RuleEngine.system : RuleEngine.systemCommand
        if let system = systemRules.match(keyCode: event.keyCode, modifiers: event.modifiers),
           event.modifiers != windowsKeyModifier.flag ||
           (modifiers.isDown(windowsKeyModifier == .option ? .leftOption : .leftCommand) &&
            !modifiers.isDown(windowsKeyModifier == .option ? .rightOption : .rightCommand)) {
            return system
        }
        guard context.mode.allowsTranslation else { return nil }
        let extraRules = windowsKeyModifier == .option ? RuleEngine.systemExtras : RuleEngine.systemExtrasCommand
        if event.modifiers == windowsKeyModifier.flag,
           modifiers.isDown(windowsKeyModifier == .option ? .leftOption : .leftCommand),
           !modifiers.isDown(windowsKeyModifier == .option ? .rightOption : .rightCommand),
           let extra = extraRules.match(keyCode: event.keyCode, modifiers: event.modifiers) {
            switch extra.id {
            case "windows.winR" where winRunEnabled: return extra
            case "windows.winI" where winSettingsEnabled: return extra
            case "windows.winTab" where winTaskViewEnabled: return extra
            default: break
            }
        }
        if altF4Enabled && event.keyCode == 118 && event.modifiers == windowsKeyModifier.altFlag {
            return windowsKeyModifier == .option ? WindowsCompatibilityRules.altF4Command : WindowsCompatibilityRules.altF4
        }
        if context.bundleID == "com.apple.finder" {
            if finderEnabled {
                let finderRules = windowsKeyModifier == .option ? RuleEngine.finderCommandAlt : RuleEngine.finder
                if let rule = finderRules.match(keyCode: event.keyCode, modifiers: event.modifiers) {
                    return rule
                }
                if let rule = RuleEngine.finderExtras.match(keyCode: event.keyCode, modifiers: event.modifiers) {
                    if rule.action == .finder(.permanentDelete) && !finderPermanentDeleteEnabled { return nil }
                    return rule
                }
                if textNavigationEnabled {
                    if let extra = RuleEngine.textNavigation.match(keyCode: event.keyCode, modifiers: event.modifiers) { return extra }
                    if let general = rules.match(keyCode: event.keyCode, modifiers: event.modifiers),
                       Self.isTextNavigation(general) { return general }
                }
                return nil
            }
            // Keep the old, non-stateful fallback until Finder actions are enabled.
            if event.keyCode == 7 { return nil }
            return localRule(event)
        }
        let browserRules = windowsKeyModifier == .option ? RuleEngine.browserCommandAlt : RuleEngine.browser
        if context.isBrowser, let browser = browserRules.match(keyCode: event.keyCode, modifiers: event.modifiers) {
            return browser
        }
        return localRule(event)
    }

    private func localRule(_ event: KeyboardEvent) -> ShortcutRule? {
        if textNavigationEnabled, let rule = RuleEngine.textNavigation.match(keyCode: event.keyCode, modifiers: event.modifiers) { return rule }
        let rule = rules.match(keyCode: event.keyCode, modifiers: event.modifiers)
        if !textNavigationEnabled, let rule, Self.isTextNavigation(rule) { return nil }
        return rule
    }

    private static func isTextNavigation(_ rule: ShortcutRule) -> Bool {
        (32...41).contains(Int(rule.id.split(separator: ".").last ?? "") ?? -1)
    }

    private func rewrite(_ event: KeyboardEvent, rule: ShortcutRule) -> EventDecision {
        var outputModifiers = event.modifiers
        // Consume the actual input modifiers (Option navigation included), never rematch output.
        let trigger = rule.input.modifiers.subtracting(.shift)
        if trigger.isEmpty || event.modifiers.isSuperset(of: trigger) {
            outputModifiers.subtract(rule.input.modifiers)
            var added = rule.output.modifiers
            if rule.input.modifiers.contains(.shift) && !event.modifiers.contains(.shift) { added.remove(.shift) }
            outputModifiers.formUnion(added)
        }
        return .rewrite(keyCode: rule.output.keyCode, modifiers: outputModifiers, ruleID: rule.id)
    }
}
