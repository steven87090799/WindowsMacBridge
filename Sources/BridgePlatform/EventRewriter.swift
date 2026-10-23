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
    /// Rebuild a *keyboard* event rather than attaching explicit Unicode text.
    /// AppKit treats Unicode-override events as text input and can reject them
    /// as menu key equivalents, even when their characters and flags look right.
    public static func clipboardReplacement(for event: CGEvent, keyCode: UInt16,
                                             modifiers: Modifiers, marker: Int64) -> CGEvent? {
        guard event.type == .keyDown || event.type == .keyUp,
              [UInt16(8), 7, 9, 0].contains(keyCode),
              modifiers == .command || (event.type == .keyUp && modifiers.isEmpty),
              let source = CGEventSource(stateID: .privateState) else { return nil }
        source.keyboardType = UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeyboardType))
        guard let output = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: event.type == .keyDown) else { return nil }
        output.timestamp = event.timestamp
        output.location = event.location
        output.flags = event.flags
        for field: CGEventField in [.eventTargetUnixProcessID, .eventTargetProcessSerialNumber, .keyboardEventAutorepeat] {
            output.setIntegerValueField(field, value: event.getIntegerValueField(field))
        }
        apply(to: output, keyCode: keyCode, modifiers: modifiers, marker: marker)
        return output
    }
}
