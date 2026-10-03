import CoreGraphics
import ApplicationServices
import Darwin
import BridgeCore
import Foundation

/// EventTap creation can succeed after macOS removes unauthorized keyboard
/// events from the requested mask. Check the granted mask outside callbacks.
public enum KeyboardEventTapCoverage {
    private static let logger = BoundedDiagnosticLogger(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WindowsMacBridge/KeyboardBackend.log"))
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
            $0.options == .defaultTap && $0.enabled && $0.eventsOfInterest & requiredEvents != 0
        }
        // WindowServer can retain disabled predecessors during replacement. They
        // cannot receive input and must not reject an enabled, complete new tap.
        // Every enabled sibling must still have the full keyboard mask.
        return !relevant.isEmpty && relevant.allSatisfy { includesKeyboardEvents($0.eventsOfInterest) }
    }

    public static func currentProcessIsVerified(tap: CFMachPort,
                                                tapPoint: CGEventTapLocation = .cgAnnotatedSessionEventTap) -> Bool {
        // A ready sibling must never stand in for the caller's disabled tap.
        guard CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) else { return false }
        // One bounded query only when creating a tap; no polling or input reads.
        var entries = [CGEventTapInformation](repeating: .init(), count: 128)
        var count: UInt32 = 0
        let result = CGGetEventTapList(UInt32(entries.count), &entries, &count)
        guard result == .success, count > 0, Int(count) <= entries.count else {
            logger.log("Tap registry unavailable: result=\(result.rawValue), count=\(count)")
            return false
        }
        let snapshot = Array(entries.prefix(Int(count)))
        let verified = isVerified(snapshot, processID: getpid(), tapPoint: tapPoint)
        if !verified {
            let own = snapshot.filter { $0.tappingProcess == getpid() }.prefix(4).map {
                "id=\($0.eventTapID),point=\($0.tapPoint.rawValue),options=\($0.options.rawValue),mask=\(String($0.eventsOfInterest, radix: 16)),enabled=\($0.enabled)"
            }.joined(separator: ";")
            logger.log("Keyboard tap verification failed: AX=\(AXIsProcessTrusted()), listen=\(CGPreflightListenEventAccess()), post=\(CGPreflightPostEventAccess()), registryCount=\(count), own=[\(own)]")
        }
        return verified
    }
}
