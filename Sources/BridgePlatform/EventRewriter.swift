import CoreGraphics
import BridgeCore

/// Mutates the current event and returns it through the tap. Never posts globally.
public enum EventRewriter {
    public static func apply(to event: CGEvent, keyCode: UInt16, modifiers: Modifiers, marker: Int64) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.flags = InputEngine.replacingModifiers(event.flags, with: modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }
}
