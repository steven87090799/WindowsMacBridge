import CoreGraphics
import Darwin

/// EventTap creation can succeed after macOS removes unauthorized keyboard
/// events from the requested mask. Check the granted mask outside callbacks.
public enum KeyboardEventTapCoverage {
    public static let requiredEvents: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.flagsChanged.rawValue)

    public static func includesKeyboardEvents(_ mask: CGEventMask) -> Bool {
        mask & requiredEvents == requiredEvents
    }

    public static func isVerified(_ entries: [CGEventTapInformation], processID: pid_t,
                                  tapPoint: CGEventTapLocation = .cgAnnotatedSessionEventTap) -> Bool {
        let relevant = entries.filter {
            $0.tappingProcess == processID && $0.tapPoint == tapPoint &&
            $0.options == .defaultTap && $0.eventsOfInterest & requiredEvents != 0
        }
        return !relevant.isEmpty && relevant.allSatisfy { $0.enabled && includesKeyboardEvents($0.eventsOfInterest) }
    }

    public static func currentProcessIsVerified(tapPoint: CGEventTapLocation = .cgAnnotatedSessionEventTap) -> Bool {
        // One bounded query only when creating a tap; no polling or input reads.
        var entries = [CGEventTapInformation](repeating: .init(), count: 128)
        var count: UInt32 = 0
        guard CGGetEventTapList(UInt32(entries.count), &entries, &count) == .success,
              count > 0, Int(count) <= entries.count else { return false }
        return isVerified(Array(entries.prefix(Int(count))), processID: getpid(), tapPoint: tapPoint)
    }
}
