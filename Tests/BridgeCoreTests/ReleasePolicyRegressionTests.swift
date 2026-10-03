import Foundation
import Testing
import BridgeCore

struct ReleasePolicyRegressionTests {
    @Test func generationChangeCancelsCaptureWithoutReleasingSingleFlightEarly() throws {
        var lifecycle = ScreenshotCaptureLifecycle()
        lifecycle.configure(enabled: true, epoch: 1)
        let request = lifecycle.begin()
        let token = try #require(request)
        lifecycle.configure(enabled: true, epoch: 2)
        #expect(!lifecycle.isCurrent(token))
        let overlapping = lifecycle.begin(); #expect(overlapping == nil)
        let result = lifecycle.complete(token); #expect(!result)
        let next = lifecycle.begin(); #expect(next != nil)
    }
    @Test func runtimeTransitionsInvalidatePauseBackendSecureSessionAndSettingsJobs() {
        var coordinator = RuntimePolicyCoordinator()
        var input = RuntimePolicyInput()
        input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: 10, bundleID: "test", mode: .macOS)
        let first = coordinator.transition(input)
        #expect(first.permitsScreenshots)
        #expect(coordinator.transition(input).generation == first.generation)
        input.manualPassThrough = true
        let manual = coordinator.transition(input)
        #expect(manual.permitsInput && !manual.permitsShortcuts && !manual.permitsPhysicalNormalization)
        input.manualPassThrough = false
        for mutation in 0..<5 {
            switch mutation {
            case 0: input.paused.toggle()
            case 1: input.backend = .deviceHID
            case 2: input.secureInput = true
            case 3: input.session &+= 1
            default: input.settingsRevision &+= 1
            }
            let previous = coordinator.current!.generation
            let next = coordinator.transition(input)
            #expect(next.generation != previous)
        }
        #expect(!coordinator.current!.permitsShortcuts)
    }
    @Test func physicalBackendOwnershipIsExclusive() {
        #expect(KeyboardOwnership.owner(backend: .deviceHID, seized: true) == .hid)
        #expect(KeyboardOwnership.owner(backend: .deviceHID, seized: false) == .native)
        #expect(KeyboardOwnership.owner(backend: .eventTap, seized: false) == .eventTap)
    }
    @Test func finderNavigationKeepsCutButCopyAndClipboardChangeCancelIt() {
        var cut = FinderCutState()
        cut.arm(changeCount: 1, finderPID: 10, now: 0)
        for action: FinderAction in [.open, .parentFolder, .goToFolder, .newFolder, .rename] {
            cut.observe(action)
            let valid = cut.validate(changeCount: 1, finderPID: 10, now: 10)
            #expect(valid)
        }
        let moved = cut.consume(changeCount: 1, finderPID: 10, now: 20); #expect(moved)
        cut.arm(changeCount: 2, finderPID: 10, now: 0); cut.observe(.copy)
        let copied = cut.validate(changeCount: 2, finderPID: 10, now: 10); #expect(!copied)
        cut.arm(changeCount: 3, finderPID: 10, now: 0)
        let stale = cut.consume(changeCount: 4, finderPID: 10, now: 20); #expect(!stale)
    }
    @Test func imageBudgetsRejectOverflowLargeDimensionsAndDeepPixels() {
        #expect(ImageMemoryBudget.allows(width: 3840, height: 2160, bytesPerPixel: 4))
        #expect(!ImageMemoryBudget.allows(width: .max, height: .max, bytesPerPixel: 4))
        #expect(!ImageMemoryBudget.allows(width: 20000, height: 10, bytesPerPixel: 4))
        #expect(!ImageMemoryBudget.allows(width: 8000, height: 8000, bytesPerPixel: 4))
        #expect(!ImageMemoryBudget.allows(width: 8192, height: 4096, bytesPerPixel: 16))
    }
    @Test func screenshotFailureClassificationDoesNotHideFailuresAsCancellation() {
        #expect(ScreenshotFailure.classify(exitCode: 0, hasImage: false, permission: true, writable: true) == .userCancelled)
        #expect(ScreenshotFailure.classify(exitCode: 1, hasImage: false, permission: false, writable: true) == .permissionDenied)
        #expect(ScreenshotFailure.classify(exitCode: 1, hasImage: false, permission: true, writable: false) == .diskFailure)
        #expect(ScreenshotFailure.classify(exitCode: 5, hasImage: false, permission: true, writable: true) == .processFailure)
    }
}

struct FinderMenuRegressionTests {
    @Test func excessivePathSelectionIsRejectedBeforeJoining() {
        let urls = (0..<1025).map { URL(fileURLWithPath: "/tmp/\($0)") }
        #expect(FinderPathSelection.selected(urls) == nil)
        let large = (0..<1024).map { URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 2048) + "\($0)") }
        #expect(FinderPathSelection.selected(large) == nil)
    }
}

struct BackendHandoffRegressionTests {
    @Test func newOwnerOfEitherBackendWaitsForTheOldHIDRelease() {
        var input = RuntimePolicyInput(); input.shortcutEnabled = true; input.screenshotEnabled = true
        input.foreground = .init(processID: 1, bundleID: "test", mode: .macOS)
        input.hidReleasePending = true
        var policy = RuntimePolicyCoordinator()
        // HID -> EventTap: translated VirtualHID output must not be translated again.
        let normal = policy.transition(input)
        #expect(!normal.permitsInput && !normal.permitsScreenshots)
        input.backend = .deviceHID
        let blocked = policy.transition(input)
        #expect(!blocked.permitsInput && !blocked.permitsScreenshots)
        input.hidReleasePending = false
        let released = policy.transition(input)
        #expect(released.permitsInput && released.permitsScreenshots && released.generation != blocked.generation)
    }
}

struct InputSourceWorkPolicyTests {
    @Test func backendFocusPauseAndSessionInvalidateGuardWorkButOwnLayoutNotificationDoesNot() {
        var input = RuntimePolicyInput()
        var policy = RuntimePolicyCoordinator()
        let first = policy.transition(input).sourceWorkPolicy
        input.layoutIdentity = "com.apple.keylayout.ABC"; input.layoutSupported = false
        #expect(policy.transition(input).sourceWorkPolicy == first)
        for change in 0..<4 {
            switch change {
            case 0: input.backend = .deviceHID
            case 1: input.foreground.processID = 71
            case 2: input.paused = true
            default: input.session += 1
            }
            #expect(policy.transition(input).sourceWorkPolicy != first)
        }
    }
}

struct RuntimeWakeRegressionTests {
    @Test func disabledPausedAndInactivePoliciesDoNotPollButKeepRecoveryDeadlines() {
        var input = RuntimePolicyInput()
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        input.shortcutEnabled = true
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        input.secureInput = true
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        input.paused = true
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: 1234) == .deadline(1234))
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: true, deadline: nil) == .stopped)
        input.paused = false; input.sessionActive = false
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
        input.sessionActive = true
        #expect(RuntimeWakePlan.make(input: input, awaitingMappingNeutral: false, deadline: nil) == .stopped)
    }
}

struct FinderCutEpochRegressionTests {
    @Test func navigationPreservesCutButPauseSessionAndBackendEpochChangesInvalidateIt() {
        var cut = FinderCutState()
        cut.synchronize(epoch: 1)
        cut.arm(changeCount: 42, finderPID: 7, now: 0)
        for action: FinderAction in [.open, .parentFolder, .goToFolder] {
            cut.observe(action); cut.synchronize(epoch: 1)
        }
        let preserved = cut.consume(changeCount: 42, finderPID: 7, now: 1); #expect(preserved)
        for epoch: UInt64 in [2, 3, 4] {
            cut.arm(changeCount: 42, finderPID: 7, now: 2)
            cut.synchronize(epoch: epoch)
            let stale = cut.consume(changeCount: 42, finderPID: 7, now: 3); #expect(!stale)
        }
    }
}

struct ScreenshotNoninteractiveFailureTests {
    @Test func unattendedCaptureWithoutAnImageIsProcessFailureRatherThanUserCancel() {
        #expect(ScreenshotFailure.classify(exitCode: 0, hasImage: false, permission: true,
            writable: true, interactive: false) == .processFailure)
        #expect(ScreenshotFailure.classify(exitCode: 0, hasImage: false, permission: true,
            writable: true, interactive: true) == .userCancelled)
    }
}
