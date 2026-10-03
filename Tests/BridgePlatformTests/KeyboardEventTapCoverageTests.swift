import CoreGraphics
import Testing
@testable import BridgePlatform

struct KeyboardEventTapCoverageTests {
    @Test func modifierOnlyTapCannotBeReportedAsKeyboardReady() {
        #expect(!KeyboardEventTapCoverage.includesKeyboardEvents(1 << CGEventType.flagsChanged.rawValue))
        #expect(!KeyboardEventTapCoverage.includesKeyboardEvents(1 << CGEventType.keyDown.rawValue))
        #expect(KeyboardEventTapCoverage.includesKeyboardEvents(KeyboardEventTapCoverage.requiredEvents))
    }

    @Test func unrelatedTapDoesNotProveTheCurrentProcessCanReceiveKeys() {
        let full = KeyboardEventTapCoverage.requiredEvents
        var entry = CGEventTapInformation()
        entry.tappingProcess = 123
        entry.tapPoint = .cgAnnotatedSessionEventTap
        entry.options = .defaultTap
        entry.eventsOfInterest = full
        entry.enabled = true
        #expect(!KeyboardEventTapCoverage.isVerified([entry], processID: 456))
        #expect(KeyboardEventTapCoverage.isVerified([entry], processID: 123))
        var restricted = entry
        restricted.eventsOfInterest = 1 << CGEventType.flagsChanged.rawValue
        #expect(!KeyboardEventTapCoverage.isVerified([entry, restricted], processID: 123))
        entry.enabled = false
        #expect(!KeyboardEventTapCoverage.isVerified([entry], processID: 123))
    }

    @Test func disabledRetiringTapDoesNotRejectReadyReplacement() {
        // Native toggle reproduction: the registry briefly retains the disabled
        // predecessor after a complete, enabled replacement has been created.
        var replacement = CGEventTapInformation()
        replacement.tappingProcess = 123
        replacement.tapPoint = .cgAnnotatedSessionEventTap
        replacement.options = .defaultTap
        replacement.eventsOfInterest = KeyboardEventTapCoverage.requiredEvents
        replacement.enabled = true
        var retiring = replacement
        retiring.enabled = false
        #expect(KeyboardEventTapCoverage.isVerified([replacement, retiring], processID: 123))
        #expect(!KeyboardEventTapCoverage.isVerified([retiring], processID: 123))
        retiring.eventsOfInterest = 1 << CGEventType.flagsChanged.rawValue
        #expect(KeyboardEventTapCoverage.isVerified([replacement, retiring], processID: 123))
        retiring.enabled = true
        #expect(!KeyboardEventTapCoverage.isVerified([replacement, retiring], processID: 123))
    }
}
