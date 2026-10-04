import Testing
import HIDLifecycle

struct LifecycleTests {
    private func valid() -> CapturePrerequisites {
        var value = CapturePrerequisites()
        value.sessionActive = true; value.secureInput = false; value.permissions = true
        value.authenticatedController = true; value.driverReady = true; value.keysNeutral = true
        value.enabled = true; value.lastHeartbeat = 10
        return value
    }
    @Test func noCaptureWithoutDriverAndNeutralKeys() {
        var lifecycle = CaptureLifecycle()
        var requirements = valid(); requirements.driverReady = false
        #expect(lifecycle.update(requirements, now: 10) == [])
        #expect(lifecycle.phase == .waitingForDriver)
        requirements.driverReady = true; requirements.keysNeutral = false
        #expect(lifecycle.update(requirements, now: 10) == [])
        #expect(lifecycle.phase == .waitingForNeutral)
        requirements.keysNeutral = true
        #expect(lifecycle.update(requirements, now: 10) == [.openPhysicalDevices])
        #expect(lifecycle.update(requirements, now: 10) == [])
        #expect(lifecycle.captureCompleted(success: true) == [])
        #expect(lifecycle.phase == .capturing)
    }
    @Test func disconnectSleepPermissionAndSecureInputReleaseBeforeClose() {
        for reason in 0..<5 {
            var lifecycle = CaptureLifecycle()
            var requirements = valid()
            _ = lifecycle.update(requirements, now: 10)
            _ = lifecycle.captureCompleted(success: true)
            switch reason {
            case 0: requirements.driverReady = false
            case 1: requirements.sessionActive = false
            case 2: requirements.permissions = false
            case 3: requirements.secureInput = true
            default: requirements.authenticatedController = false
            }
            #expect(lifecycle.update(requirements, now: 10) == [.releaseVirtualOutputs, .closePhysicalDevices])
            #expect(lifecycle.update(requirements, now: 10) == [])
        }
    }
    @Test func staleHeartbeatAndClockRollbackNeverCapture() {
        var lifecycle = CaptureLifecycle()
        let requirements = valid()
        #expect(lifecycle.update(requirements, now: 11) == [])
        #expect(lifecycle.update(requirements, now: 9) == [])
        _ = lifecycle.update(requirements, now: 10)
        _ = lifecycle.captureCompleted(success: true)
        #expect(lifecycle.update(requirements, now: 11) == [.releaseVirtualOutputs, .closePhysicalDevices])
    }
    @Test func partialOpenFailureRequiresExplicitRestart() {
        var lifecycle = CaptureLifecycle()
        let requirements = valid()
        _ = lifecycle.update(requirements, now: 10)
        #expect(lifecycle.captureCompleted(success: false) == [.releaseVirtualOutputs, .closePhysicalDevices])
        #expect(lifecycle.update(requirements, now: 10) == [])
        #expect(lifecycle.phase == .faulted)
        #expect(lifecycle.restart() == [])
        #expect(lifecycle.update(requirements, now: 10) == [.openPhysicalDevices])
        #expect(lifecycle.stop() == [.releaseVirtualOutputs, .closePhysicalDevices])
    }
    @Test func keyPressedDuringSeizeAbortsWithoutRequiringRestart() {
        var lifecycle = CaptureLifecycle()
        let requirements = valid()
        #expect(lifecycle.update(requirements, now: 10) == [.openPhysicalDevices])
        #expect(lifecycle.captureAborted() == [.releaseVirtualOutputs, .closePhysicalDevices])
        #expect(lifecycle.phase == .waitingForNeutral)
        // No explicit restart is needed once the keys are neutral again.
        #expect(lifecycle.update(requirements, now: 10) == [.openPhysicalDevices])
        #expect(lifecycle.captureCompleted(success: true) == [] && lifecycle.phase == .capturing)
        // Only a pending open can be aborted.
        #expect(lifecycle.captureAborted() == [] && lifecycle.phase == .capturing)
    }
    @Test func oneKeyboardDisconnectDoesNotStopAnotherCapturedKeyboard() {
        var lifecycle = CaptureLifecycle()
        _ = lifecycle.update(valid(), now: 10); _ = lifecycle.captureCompleted(success: true)
        #expect(lifecycle.deviceRemoved(remainingCaptured: true) == [] && lifecycle.phase == .capturing)
        #expect(lifecycle.deviceRemoved(remainingCaptured: false) == [.releaseVirtualOutputs, .closePhysicalDevices])
        #expect(lifecycle.phase == .inactive)
    }
}

struct HeldSafetyPolicyTests {
    @Test func neutralIdleHasNoDeadline() {
        #expect(HeldSafetyPolicy.deadline(capturing: true, heldOutput: false, pointingButtons: 0, outstandingReports: 0) == nil)
        #expect(HeldSafetyPolicy.deadline(capturing: false, heldOutput: true, pointingButtons: 1, outstandingReports: 9) == nil)
    }
    @Test func onlyAPointingButtonHeldStillArmsTheGuard() {
        #expect(HeldSafetyPolicy.deadline(capturing: true, heldOutput: false, pointingButtons: 1, outstandingReports: 0) == HeldSafetyPolicy.heldDeadline)
    }
    @Test func finalKeyUpOrButtonUpStillOutstandingArmsTheShortDeadline() {
        // keydown -> keyup (or button down -> up): nothing is held any more, but the
        // release report has not been completed by the driver.
        #expect(HeldSafetyPolicy.deadline(capturing: true, heldOutput: false, pointingButtons: 0, outstandingReports: 1) == HeldSafetyPolicy.outstandingDeadline)
        #expect(HeldSafetyPolicy.deadline(capturing: true, heldOutput: true, pointingButtons: 1, outstandingReports: 256) == HeldSafetyPolicy.outstandingDeadline)
        #expect(HeldSafetyPolicy.outstandingDeadline > 0.5 && HeldSafetyPolicy.outstandingDeadline < HeldSafetyPolicy.heldDeadline)
    }
}
