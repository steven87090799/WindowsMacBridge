/// Input-thread confined in production; a deterministic value type in tests.
/// No synthetic modifier ownership exists in this first release.
public struct KeyboardEventProcessor: Sendable {
    private struct Press: Sendable {
        var rule: ShortcutRule?
        var contextPID: Int32
        var contextBundle: String
        var contextMode: ApplicationMode
        var suppress: Bool
    }
    private var presses = [Press?](repeating: nil, count: 128)
    private var context = ApplicationContext()
    private var enabled = false
    private var layoutSupported = false
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
                                   layoutSupported: Bool) {
        let changedContext = context.processID != newContext.processID ||
            context.bundleID != newContext.bundleID || context.mode != newContext.mode
        if changedContext {
            // Once a focus transaction ends, returning to the same PID must not revive it.
            for i in presses.indices where presses[i]?.rule != nil { presses[i]?.suppress = true }
        }
        if changedContext || self.enabled != enabled || self.layoutSupported != layoutSupported {
            awaitingNeutral = true
        }
        context = newContext; self.enabled = enabled; self.layoutSupported = layoutSupported
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

    public mutating func process(_ event: KeyboardEvent) -> EventDecision {
        if event.isOwnEvent { return .passThrough }
        processedCount &+= 1
        if event.phase == .flagsChanged {
            if let side = event.modifierSide, let down = event.modifierDown {
                modifiers.observe(side, down: down, aggregate: event.modifiers)
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
            if event.phase == .down && (!enabled || !layoutSupported) { return .suppress }
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
        if event.keyCode == 35 && event.modifiers == [.control, .option, .command] {
            presses[index] = Press(rule: nil, contextPID: context.processID,
                                   contextBundle: context.bundleID, contextMode: context.mode, suppress: true)
            pressCount += 1
            enabled = false; awaitingNeutral = true
            return .emergencyPause
        }
        if event.modifiers.isEmpty && activePressCount == 0 { awaitingNeutral = false }

        // Finder X is intentionally excluded until a safe file/text focus adapter exists.
        let finderCut = context.bundleID == "com.apple.finder" && event.keyCode == 7
        let rule = enabled && layoutSupported && !awaitingNeutral && modifiers.synchronized &&
            context.mode.allowsTranslation && !finderCut
            ? rules.match(keyCode: event.keyCode, modifiers: event.modifiers) : nil
        presses[index] = Press(rule: rule, contextPID: context.processID,
                               contextBundle: context.bundleID, contextMode: context.mode, suppress: false)
        pressCount += 1
        guard let rule else { return .passThrough }
        translatedCount &+= 1
        return rewrite(event, rule: rule)
    }

    private func rewrite(_ event: KeyboardEvent, rule: ShortcutRule) -> EventDecision {
        var outputModifiers = event.modifiers
        // Do not resurrect Command/Shift if the physical Control has already been released.
        if event.modifiers.contains(.control) {
            outputModifiers.remove(.control)
            outputModifiers.formUnion(rule.output.modifiers)
        }
        return .rewrite(keyCode: rule.output.keyCode, modifiers: outputModifiers, ruleID: rule.id)
    }
}
