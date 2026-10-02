import Testing
@testable import BridgeCore

struct HIDDescriptorTests {
    private func element(_ page: UInt32, _ usage: UInt32, min: Int = 0, max: Int = 1, relative: Bool = false) -> HIDElementDescriptor {
        .init(page: page, usage: usage, minimum: min, maximum: max, relative: relative)
    }
    @Test func standardKeyboardMouseCompositeHasNoDiscardedInput() {
        let elements = [element(7, 4), element(7, 0xe0), element(9, 1),
                        element(1, 0x30, min: -127, max: 127, relative: true),
                        element(1, 0x31, min: -127, max: 127, relative: true),
                        element(1, 0x38, min: -127, max: 127, relative: true),
                        element(12, 0x238, min: -127, max: 127, relative: true)]
        #expect(HIDDescriptorPolicy.accepts(elements))
        #expect(elements.map(\.role) == [.key, .key, .button, .x, .y, .wheel, .pan])
    }
    @Test func unknownAbsoluteTouchAndUnrepresentableInputPreventSeize() {
        for unsafe in [element(1, 0x30, max: 32767), element(13, 0x30), element(0xff00, 2),
                       element(9, 33), element(1, 0x30, min: -32768, max: 32767, relative: true)] {
            #expect(!HIDDescriptorPolicy.accepts([element(7,4), unsafe]))
        }
        #expect(!HIDDescriptorPolicy.accepts([element(9,1)]))
        #expect(!HIDDescriptorPolicy.accepts(Array(repeating: element(7,4), count: 2049)))
    }
    @Test func scannerKeysAndConsumerKeysPreserveValidNonBooleanRanges() {
        #expect(element(7, 4, max: 255).role == .key)
        #expect(element(12, 0xe9).role == .key)
        #expect(element(7, 0, max: 255).role == .unsupported)
        #expect(element(0xff01, 3).role == .key)
    }
    @Test func pointingButtonsHaveIndependentDeviceOwnershipAndMotionIsBounded() {
        var state = HIDPointingLedger()
        let registeredA = state.register(1), registeredB = state.register(2)
        #expect(registeredA && registeredB)
        let downA = state.observe(device: 1, role: .button, usage: 1, value: 1)
        let downB = state.observe(device: 2, role: .button, usage: 1, value: 1)
        #expect(downA && downB)
        state.disconnect(1)
        #expect(state.buttons == 1)
        let up = state.observe(device: 2, role: .button, usage: 1, value: 0)
        #expect(up && state.buttons == 0)
        let invalid = state.observe(device: 2, role: .x, usage: 0x30, value: 1024)
        #expect(!invalid)
        state.reset()
        #expect(state.buttons == 0)
    }
}
