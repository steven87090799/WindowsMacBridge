/// A native Cmd+Tab session owns one synthetic Command side until physical Alt release.
/// No window enumeration, custom MRU list, timer or App switching UI is involved.
public struct NativeAppSwitchLatch: Sendable {
    private var held = false
    private var key: UInt16 = 55
    private var target: Int32 = 0
    public init() {}
    public func isActive(for target: Int32) -> Bool { held && self.target == target }
    public mutating func apply(_ original: EventDecision, event: KeyboardEvent,
                               state: ModifierStateMachine, target: Int32) -> EventDecision {
        if case .rewrite(_, _, "windows.nativeAppSwitch") = original, event.phase == .down {
            if !held { key = state.isDown(.rightOption) && !state.isDown(.leftOption) ? 54 : 55; self.target = target }
            held = true
        }
        guard held else { return original }
        let flags = event.modifiers.subtracting(.option).union(event.modifiers.contains(.option) ? .command : [])
        var decision = original
        if event.phase == .flagsChanged {
            let outputKey = event.modifierSide?.group == .option ? key : event.keyCode
            decision = .rewrite(keyCode: outputKey, modifiers: flags, ruleID: "windows.nativeAppSwitch.modifier")
        } else if original == .passThrough {
            decision = .rewrite(keyCode: event.keyCode, modifiers: flags, ruleID: "windows.nativeAppSwitch.held")
        }
        if !event.modifiers.contains(.option) { held = false }
        return decision
    }
    public mutating func drain(_ release: (UInt16, Modifiers, Int32) -> Void) {
        if held { release(key, [], target) }
        held = false; target = 0
    }
}
