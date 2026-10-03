import Testing
import HIDLifecycle

struct ConnectionLeaseTests {
    @Test func authenticatedConnectionCanStayNeutralWithoutHeartbeatPackets() {
        var prerequisites = CapturePrerequisites()
        prerequisites.enabled = true; prerequisites.sessionActive = true
        prerequisites.secureInput = false; prerequisites.permissions = true
        prerequisites.authenticatedController = true; prerequisites.driverReady = true
        prerequisites.keysNeutral = true; prerequisites.connectionLeaseValid = true
        var lifecycle = CaptureLifecycle()
        #expect(lifecycle.update(prerequisites, now: 100_000) == [.openPhysicalDevices])
        #expect(lifecycle.captureCompleted(success: true).isEmpty)
        prerequisites.connectionLeaseValid = false
        #expect(lifecycle.update(prerequisites, now: 100_001) == [.releaseVirtualOutputs, .closePhysicalDevices])
    }
    @Test func connectionFlagCannotBypassAuthentication() {
        var prerequisites = CapturePrerequisites()
        prerequisites.connectionLeaseValid = true
        #expect(!prerequisites.leaseValid(at: 10))
    }
}
