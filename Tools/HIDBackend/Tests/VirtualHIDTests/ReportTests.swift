import Testing
import Darwin
import VirtualHID

struct ReportTests {
    @Test func rolloverReleasesOldKeysThenModifiersBeforeNewChord() {
        var old = WMBHIDState(); old.modifiers = 8; old.key_count = 1; old.keys.0 = 6
        var next = WMBHIDState(); next.modifiers = 4; next.key_count = 1; next.keys.0 = 0x4f
        var reports = [WMBHIDState](repeating: .init(), count: 3)
        #expect(wmb_plan_state_transition(&old, &next, &reports, reports.count) == 3)
        #expect(reports[0].key_count == 0 && reports[0].modifiers == 8)
        #expect(reports[1].key_count == 0 && reports[1].modifiers == 0)
        #expect(reports[2].key_count == 1 && reports[2].modifiers == 4 && reports[2].keys.0 == 0x4f)
        #expect(wmb_plan_state_transition(&old, &next, &reports, 2) == 0)
        next.modifiers = 8
        #expect(wmb_plan_state_transition(&old, &next, &reports, reports.count) == 1)
    }
    @Test func vendorAndDesktopEventsArePreservedAndBounded() {
        var state = WMBHIDState()
        state.fn = true; state.top_case_count = 1; state.top_case_keys.0 = 8
        state.vendor_count = 1; state.vendor_keys.0 = 0x10
        state.desktop_count = 1; state.desktop_keys.0 = 0x81
        var output = [UInt8](repeating: 0, count: 80)
        #expect(wmb_encode_fn(&state, &output, output.count) == 65)
        #expect(Array(output[1..<5]) == [3,0,8,0])
        #expect(wmb_encode_vendor(&state, &output, output.count) == 65)
        #expect(output[1] == 0x10)
        #expect(wmb_encode_desktop(&state, &output, output.count) == 65)
        #expect(output[1] == 0x81)
        state.vendor_count = 33; #expect(!wmb_validate_state(&state))
        state.vendor_count = 1; state.top_case_keys.0 = 3; #expect(!wmb_validate_state(&state))
    }
    @Test func keyboardReportMatchesUSBLayoutAndPreservesBothCommandSides() {
        var state = WMBHIDState()
        state.modifiers = 0x88
        state.key_count = 2
        state.keys.0 = 0x06 // C
        state.keys.1 = 0x19 // V
        var output = [UInt8](repeating: 0xff, count: 80)
        #expect(wmb_encode_keyboard(&state, &output, output.count) == 67)
        #expect(Array(output.prefix(7)) == [1, 0x88, 0, 6, 0, 0x19, 0])
        #expect(output[67] == 0xff)
    }
    @Test func fnUsesAppleTopCaseReportAndReleaseIsEmpty() {
        var state = WMBHIDState(); state.fn = true
        var output = [UInt8](repeating: 0xff, count: 80)
        #expect(wmb_encode_fn(&state, &output, output.count) == 65)
        #expect(Array(output.prefix(3)) == [3, 3, 0])
        state.fn = false
        #expect(wmb_encode_fn(&state, &output, output.count) == 65)
        #expect(output[0] == 3)
        #expect(output[1..<65].allSatisfy { $0 == 0 })
    }
    @Test func consumerBrightnessHasItsOwnReport() {
        var state = WMBHIDState()
        state.consumer_count = 1; state.consumer_keys.0 = 0x6f
        var output = [UInt8](repeating: 0xff, count: 80)
        #expect(wmb_encode_consumer(&state, &output, output.count) == 65)
        #expect(Array(output.prefix(3)) == [2, 0x6f, 0])
        state.consumer_count = 0
        #expect(wmb_encode_consumer(&state, &output, output.count) == 65)
        #expect(output[1..<65].allSatisfy { $0 == 0 })
    }
    @Test func invalidReportsAndShortBuffersAreRejectedWithoutWrites() {
        var state = WMBHIDState(); state.key_count = 33
        #expect(!wmb_validate_state(&state))
        var output = [UInt8](repeating: 0xfe, count: 128)
        #expect(wmb_encode_keyboard(&state, &output, output.count) == 0)
        #expect(output.allSatisfy { $0 == 0xfe })
        state.key_count = 1; state.keys.0 = 0xe0
        #expect(!wmb_validate_state(&state))
        state.keys.0 = 4; state.key_count = 2; state.keys.1 = 4
        #expect(!wmb_validate_state(&state))
        state.key_count = 0
        #expect(wmb_encode_fn(&state, &output, 1) == 0)
        #expect(output.allSatisfy { $0 == 0xfe })
        #expect(!wmb_virtual_hid_post(nil, &state))
    }
    @Test func hundredThousandReportsDoNotConnectOrInject() {
        var state = WMBHIDState(); state.key_count = 1; state.keys.0 = 6
        var output = [UInt8](repeating: 0, count: 80)
        for i in 0..<100_000 {
            state.modifiers = UInt8(i & 255)
            #expect(wmb_encode_keyboard(&state, &output, output.count) == 67)
            #expect(output[1] == state.modifiers)
        }
    }
    @Test func unprivilegedClientRefusesToConnect() {
        if geteuid() != 0 { #expect(wmb_virtual_hid_create() == nil) }
        #expect(wmb_client_protocol_version() == 7)
        #expect(wmb_driver_version() == 10800)
    }
}
