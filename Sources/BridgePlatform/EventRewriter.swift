import CoreGraphics
import BridgeCore

/// Mutates the current event and returns it through the tap. Never posts globally.
public enum EventRewriter {
    /// One process-wide marker for every backend and downstream tap. A translated
    /// Ctrl+Shift+S must not be mistaken for an original Command+Shift+S event.
    public static let generatedEventMarker = Int64.random(in: 1...Int64.max)

    public static func isGeneratedByBridge(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == generatedEventMarker
    }

    public static func apply(to event: CGEvent, keyCode: UInt16, modifiers: Modifiers, marker: Int64) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.flags = InputEngine.replacingModifiers(event.flags, with: modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }
}
