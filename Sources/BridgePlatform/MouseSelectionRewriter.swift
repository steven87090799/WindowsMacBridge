import CoreGraphics
import BridgeCore

/// Input-thread confined. Translate only pointer events, never the held keyboard
/// modifier itself, so Ctrl+C, native right click and modifier releases stay independent.
struct MouseSelectionRewriter {
    static let events: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
        (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)

    static func handles(_ type: CGEventType) -> Bool {
        type == .leftMouseDown || type == .leftMouseUp || type == .leftMouseDragged
    }

    private struct Press {
        var processID: Int64
        var stateID: Int64
        var target: ApplicationContext
        var dragModifiers: Modifiers?
    }
    // One physical stream plus the routing snapshot's bounded 32 producers.
    private var presses = [Press?](repeating: nil, count: 33)

    mutating func invalidate() {
        for i in presses.indices { presses[i] = nil }
    }

    @discardableResult
    mutating func apply(to event: CGEvent, origin: InputSourceClass,
                        configuration: EngineConfiguration, active: Bool) -> Bool {
        guard Self.handles(event.type), !EventRewriter.isGeneratedByBridge(event) else { return false }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let state = event.getIntegerValueField(.eventSourceStateID)
        let effectiveOrigin: InputSourceClass = origin == .virtualPassThrough && pid == 0 && state == 1 &&
            configuration.destinationSemantics ? .physicalFallback : origin
        let existing = presses.firstIndex { $0?.processID == pid && $0?.stateID == state }
        let previous = existing.flatMap { presses[$0] }
        if event.type == .leftMouseDown || event.type == .leftMouseUp {
            if let existing { presses[existing] = nil }
        }

        let recipient = Int32(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        guard active, configuration.enabled, configuration.sessionActive,
              allows(effectiveOrigin, configuration: configuration),
              let context = DestinationSemanticPolicy.context(target: recipient,
                foreground: configuration.context, recipients: configuration.recipients),
              context.mode.allowsTranslation, !context.clipboardOnly else {
            if let existing { presses[existing] = nil }
            return false
        }

        let flags = InputEngine.modifiers(event.flags)
        if event.type == .leftMouseDown {
            // Only Ctrl or Ctrl+Shift; preserve Command, Option-drag and other chords.
            guard flags.subtracting(.shift) == .control,
                  let slot = presses.firstIndex(where: { $0 == nil }) else { return false }
            presses[slot] = Press(processID: pid, stateID: state, target: context)
        } else {
            // Keep the selected click's drag/up paired even if Ctrl is released first.
            // Another source or recipient cannot inherit the translated press.
            guard previous?.target == context else {
                if let existing { presses[existing] = nil }
                return false
            }
        }
        var output = flags.subtracting(.control).union(.command)
        if context.bundleID == "com.apple.finder", let existing, event.type != .leftMouseDown {
            var drag = previous?.dragModifiers
            if event.type == .leftMouseDragged, drag == nil {
                // Windows Ctrl-drag copies; Ctrl+Shift-drag creates a shortcut.
                // Latch through drop even when the keyboard modifiers release first.
                drag = flags.contains(.shift) ? [.command, .option] : .option
                presses[existing]?.dragModifiers = drag
            }
            if let drag { output = flags.subtracting([.control, .command, .shift]).union(drag) }
        }
        event.flags = InputEngine.replacingModifiers(event.flags, with: output)
        event.setIntegerValueField(.eventSourceUserData, value: EventRewriter.generatedEventMarker)
        return true
    }

    private func allows(_ origin: InputSourceClass, configuration: EngineConfiguration) -> Bool {
        switch origin {
        case .physicalFallback, .universalControl:
            // A pointer event cannot identify which keyboard supplied Ctrl. Never
            // apply a device-specific preference to every mouse on the machine.
            return configuration.keyboardScope == .allKeyboards &&
                !configuration.deviceInputs.contains { $0.experience == .nativeMac }
        case .remote(let index):
            guard configuration.inputRouting.producers.indices.contains(index) else { return false }
            let producer = configuration.inputRouting.producers[index]
            guard producer.work.isCurrentWithoutWaiting else { return false }
            switch producer.semantics {
            case .windows: return true
            case .automatic:
                return producer.confidence == .known &&
                    (producer.transport == .vnc || producer.transport == .googleRemoteDesktop)
            case .macOS, .alreadyTranslated: return false
            }
        case .bridgeOutput, .virtualPassThrough, .unknown: return false
        }
    }
}
