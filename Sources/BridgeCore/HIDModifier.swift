/// Physical modifier bits tracked by the active HID translation engine.
public enum HIDModifier: Int, CaseIterable, Sendable {
    case leftControl, rightControl, leftCommand, rightCommand
    case leftOption, rightOption, leftShift, rightShift, fn
    public var bit: UInt16 { 1 << rawValue }
}
