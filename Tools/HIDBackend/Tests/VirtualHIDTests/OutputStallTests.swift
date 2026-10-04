import Testing
import VirtualHID

/// The driver-completion stall rule behind wmb_virtual_hid_status. A held-safety
/// deadline makes DeviceCapture re-read the status, so a driver that stops
/// completing reports (including a final key-up or button-up) fails closed.
struct OutputStallTests {
    @Test func driverThatStopsCompletingIsAFaultAfterHalfASecond() {
        let start: Int64 = 1_000_000_000
        #expect(!wmb_output_stalled(0, start, start + 10_000_000_000), "neutral idle is never stalled")
        #expect(!wmb_output_stalled(1, start, start + 400_000_000))
        #expect(wmb_output_stalled(1, start, start + 600_000_000))
        #expect(wmb_output_stalled(256, start, start + 501_000_000))
    }
    @Test func completionProgressClearsTheStall() {
        let start: Int64 = 1_000_000_000
        // A completion moves last_progress forward; outstanding reaching 0 ends it.
        #expect(!wmb_output_stalled(3, start + 900_000_000, start + 1_000_000_000))
        #expect(!wmb_output_stalled(0, start, start + 900_000_000))
    }
    @Test func missingClientHasNoOutstandingOutputAndIsNotReady() {
        #expect(wmb_virtual_hid_outstanding(nil) == 0)
        #expect(wmb_virtual_hid_status(nil) & UInt32(WMB_CONNECTION_FAULT) != 0)
    }
}
