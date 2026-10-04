// Adapted from vchewing-input-helper @ 43779320 (MIT), converted from XCTest.
import Testing
@testable import InputSourceCore

struct GuardStateMachineTests {
    @Test func externalABCDoesNotReplaceGuardTarget() {
        var machine = GuardStateMachine()
        _ = machine.observeExternalSelection(.abc)
        #expect(machine.desired == .vChewing)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.beginSelectionAttempt() == 1)
    }
    @Test func externalSelectionCannotEraseExplicitEnglishIntent() {
        var machine = GuardStateMachine()
        machine.request(.abc)
        _ = machine.observeExternalSelection(.vChewing)
        #expect(machine.desired == .abc)
        #expect(machine.observe(.vChewing, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
    }
    @Test func resumeCorrectsEnglishInsteadOfAdoptingIt() {
        var machine = GuardStateMachine()
        machine.setEnabled(false)
        _ = machine.observeExternalSelection(.abc)
        machine.setEnabled(true)
        #expect(machine.desired == .vChewing)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
    }
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
    @Test func pauseAndResumeRetainsExplicitABC() {
        var machine = GuardStateMachine()
        machine.request(.abc)
        machine.setEnabled(false)
        #expect(machine.observe(.other, isInternalSwitch: false) == .ignored)
        machine.setEnabled(true)
        #expect(machine.desired == .abc)
        #expect(machine.observe(.abc, isInternalSwitch: false) == .alreadySatisfied)
        #expect(machine.observe(.vChewing, isInternalSwitch: false) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.beginSelectionAttempt() == 1)
    }
    @Test func successClearsRetryBudget() {
        var machine = GuardStateMachine()
        _ = machine.observe(.abc, isInternalSwitch: false)
        #expect(machine.beginSelectionAttempt() == 1)
        machine.selectionSucceeded()
        #expect(machine.delayBeforeNextAttempt() == nil)
        #expect(machine.beginSelectionAttempt() == nil)
    }
    @Test func externalSelectionDoesNotReplacePendingTarget() {
        var machine = GuardStateMachine()
        _ = machine.observe(.abc, isInternalSwitch: false)
        #expect(machine.beginSelectionAttempt() == 1)
        #expect(machine.observeExternalSelection(.abc) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.desired == .vChewing)
        #expect(machine.beginSelectionAttempt() == 1)
    }
    @Test func thirdPartySourceIsCorrectedAfterEnableCycle() {
        var machine = GuardStateMachine()
        machine.setEnabled(false)
        #expect(machine.observeExternalSelection(.other) == .ignored)
        machine.setEnabled(true)
        #expect(machine.desired == .vChewing)
        #expect(machine.observeExternalSelection(.other) == .scheduleDebounce(milliseconds: 400))
        #expect(machine.beginSelectionAttempt() == 1)
    }
    @Test func onlyExplicitRequestChangesTarget() {
        var machine = GuardStateMachine()
        machine.request(.abc)
        _ = machine.observeExternalSelection(.other)
        #expect(machine.desired == .abc)
        #expect(machine.beginSelectionAttempt() == 1)
        machine.request(.vChewing)
        #expect(machine.desired == .vChewing)
    }
    @Test func ownDelayedNotificationDoesNotChangeExplicitTarget() {
        var machine = GuardStateMachine()
        machine.request(.abc)
        machine.selectionSucceeded()
        #expect(machine.observe(.vChewing, isInternalSwitch: true) == .ignored)
        #expect(machine.desired == .abc)
        #expect(machine.beginSelectionAttempt() == nil)
    }
    @Test func selectingPreviousSourceDoesNotOverrideUnconfirmedOwnRequest() {
        let decision = SourceNotificationDecision.evaluate(
            current: "ABC", pendingTarget: "vChewing", waitingForExplicitSelection: false, lastObserved: "ABC"
        )
        #expect(decision == .externalChange)
        var machine = GuardStateMachine()
        machine.request(.vChewing)
        #expect(machine.beginSelectionAttempt() == 1)
        _ = machine.observeExternalSelection(.abc)
        #expect(machine.desired == .vChewing)
    }
    @Test func sourceNotificationHasNoAuthorityToReplaceSecureInputIntent() {
        #expect(SourceNotificationDecision.evaluate(
            current: "ABC", pendingTarget: nil, waitingForExplicitSelection: true, lastObserved: "ABC"
        ) == .externalChange)
    }
    @Test func ownNotificationConfirmsOnlyItsExactTarget() {
        #expect(SourceNotificationDecision.evaluate(
            current: "vChewing", pendingTarget: "vChewing", waitingForExplicitSelection: false, lastObserved: "ABC"
        ) == .ownSelectionConfirmed)
        #expect(SourceNotificationDecision.evaluate(
            current: "thirdParty", pendingTarget: "vChewing", waitingForExplicitSelection: false, lastObserved: "ABC"
        ) == .externalChange)
    }
    @Test func idleDuplicateAndUnavailableSourceDoNotChangeIntent() {
        #expect(SourceNotificationDecision.evaluate(
            current: "ABC", pendingTarget: nil, waitingForExplicitSelection: false, lastObserved: "ABC"
        ) == .unchanged)
        #expect(SourceNotificationDecision.evaluate(
            current: nil, pendingTarget: "vChewing", waitingForExplicitSelection: true, lastObserved: "ABC"
        ) == .unchanged)
    }
}
