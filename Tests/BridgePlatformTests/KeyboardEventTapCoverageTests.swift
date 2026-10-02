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
}
