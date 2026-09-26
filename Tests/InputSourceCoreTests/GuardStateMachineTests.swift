// Adapted from vchewing-input-helper @ 43779320 (MIT), converted from XCTest.
import Testing
@testable import InputSourceCore

struct GuardStateMachineTests {
    @Test func launchStartsWithTraditional() {
        var machine = GuardStateMachine()
        machine.request(.abc)
        #expect(GuardStateMachine().desired == .vChewing)
        #expect(machine.desired == .abc)
    }
    @Test func explicitToggleBothDirections() {
        var machine = GuardStateMachine()
        #expect(machine.toggleDesiredSource() == .abc)
        #expect(machine.toggleDesiredSource() == .vChewing)
    }
    @Test func mismatchDebouncesAndMatchCancels() {
        var machine = GuardStateMachine(debounceMilliseconds: 400)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.observe(.vChewing, isInternalSwitch: false) == .alreadySatisfied)
        #expect(machine.delayBeforeNextAttempt() == nil)
    }
    @Test func liveDebounceChange() {
        var machine = GuardStateMachine()
        machine.setDebounce(milliseconds: 650)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 650))
    }
    @Test func negativeDebounceClamped() {
        var machine = GuardStateMachine(debounceMilliseconds: -100)
        #expect(machine.debounceMilliseconds == 0)
        machine.setDebounce(milliseconds: -1)
        #expect(machine.debounceMilliseconds == 0)
    }
    @Test func retriesBackOffAndStop() {
        var machine = GuardStateMachine(debounceMilliseconds: 400, maximumSelectionAttempts: 3)
        _ = machine.observe(.abc, isInternalSwitch: false)
        #expect(machine.beginSelectionAttempt() == 1)
        #expect(machine.delayBeforeNextAttempt() == 800)
        #expect(machine.beginSelectionAttempt() == 2)
        #expect(machine.delayBeforeNextAttempt() == 1_600)
        #expect(machine.beginSelectionAttempt() == 3)
        #expect(machine.delayBeforeNextAttempt() == nil)
        #expect(machine.beginSelectionAttempt() == nil)
    }
    @Test func newMismatchStartsBoundedTransaction() {
        var machine = GuardStateMachine()
        _ = machine.observe(.abc, isInternalSwitch: false)
        for expected in 1...3 { #expect(machine.beginSelectionAttempt() == expected) }
        #expect(machine.beginSelectionAttempt() == nil)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.beginSelectionAttempt() == 1)
    }
    @Test func ownNotificationsDoNotLoop() {
        var machine = GuardStateMachine()
        #expect(machine.observe(.abc, isInternalSwitch: true) == .ignored)
        #expect(machine.beginSelectionAttempt() == nil)
    }
    @Test func pauseAndResumeRestoresTraditional() {
        var machine = GuardStateMachine()
        machine.request(.abc)
        machine.setEnabled(false)
        #expect(machine.observe(.other, isInternalSwitch: false) == .ignored)
        machine.setEnabled(true)
        #expect(machine.desired == .vChewing)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
    }
    @Test func successClearsRetryBudget() {
        var machine = GuardStateMachine()
        _ = machine.observe(.abc, isInternalSwitch: false)
        #expect(machine.beginSelectionAttempt() == 1)
        machine.selectionSucceeded()
        #expect(machine.delayBeforeNextAttempt() == nil)
        #expect(machine.beginSelectionAttempt() == nil)
    }
}
