import Foundation
import CoreFoundation
import Testing
import HIDLifecycle

struct RunLoopLifetimeTests {
    @Test func permissionOnlyServiceWaitsWithoutCaptureOrPolling() async {
        let result: (Bool, Bool) = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                // A fresh IPC-only thread finishes immediately without a source.
                let empty = CFRunLoopRunInMode(.defaultMode, 0, false) == .finished
                let lifetime = PassiveRunLoopLifetime()
                let waiting = withExtendedLifetime(lifetime) {
                    lifetime != nil && CFRunLoopRunInMode(.defaultMode, 0, false) == .timedOut
                }
                continuation.resume(returning: (empty, waiting))
            }
        }
        #expect(result.0)
        #expect(result.1)
    }
}
