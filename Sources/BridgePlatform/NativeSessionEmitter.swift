import CoreGraphics
import BridgeCore

/// WindowServer handles these shortcuts before annotated delivery. A checked
/// destination can send only these outputs back through native session routing.
enum NativeSessionEmitter {
    static func requiresSessionRouting(_ rule: String) -> Bool {
        switch rule {
        case "karabiner.11", "windows.winR", "windows.winTab",
             "windows.nativeAppSwitch", "windows.nativeAppSwitch.modifier", "windows.nativeAppSwitch.held": true
        default: false
        }
    }
    static func prepare(type: CGEventType, keyCode: UInt16, modifiers: Modifiers, marker: Int64) -> CGEvent? {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: type == .keyDown) else { return nil }
        event.type = type
        EventRewriter.apply(to: event, keyCode: keyCode, modifiers: modifiers, marker: marker)
        return event
    }
}
