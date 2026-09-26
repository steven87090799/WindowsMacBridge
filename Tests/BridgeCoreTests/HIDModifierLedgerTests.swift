import Testing
import BridgeCore

struct HIDModifierLedgerTests {
    private let builtIn = KeyboardDevice(registryID: 1, builtIn: true, vendorID: 1452, productID: 1)
    private let apple834 = KeyboardDevice(registryID: 2, builtIn: false, vendorID: 1452, productID: 834)
    @Test func allSixSwapsAndBothShiftsRelease() {
        var ledger = HIDModifierLedger(); #expect(ledger.register(builtIn) == true)
        let expected: [HIDModifier] = [.fn, .rightControl, .leftOption, .rightOption,
                                       .leftCommand, .rightCommand, .leftShift, .rightShift, .leftControl]
        for (input, output) in zip(HIDModifier.allCases, expected) {
            ledger.observe(deviceID: 1, modifier: input, down: true)
            #expect(ledger.reportModifiers == output.bit)
            ledger.observe(deviceID: 1, modifier: input, down: false)
            #expect(ledger.reportModifiers == 0)
        }
    }
    @Test func disconnectOnlyReleasesItsOwnOutputs() {
        var ledger = HIDModifierLedger(); _ = ledger.register(builtIn); _ = ledger.register(apple834)
        ledger.observe(deviceID: 1, modifier: .leftOption, down: true)
        ledger.observe(deviceID: 2, modifier: .leftOption, down: true)
        ledger.disconnect(1)
        #expect(ledger.reportModifiers == HIDModifier.leftCommand.bit)
        ledger.observe(deviceID: 2, modifier: .leftOption, down: false)
        #expect(ledger.reportModifiers == 0)
    }
    @Test func remoteTransitionReleasesOutputAndWaitsForNeutral() {
        var ledger = HIDModifierLedger(); _ = ledger.register(builtIn)
        ledger.observe(deviceID: 1, modifier: .fn, down: true)
        ledger.transition(mappingEnabled: false)
        #expect(ledger.reportModifiers == 0)
        ledger.observe(deviceID: 1, modifier: .leftOption, down: true)
        #expect(ledger.reportModifiers == 0)
        ledger.observe(deviceID: 1, modifier: .fn, down: false)
        ledger.observe(deviceID: 1, modifier: .leftOption, down: false)
        ledger.observe(deviceID: 1, modifier: .leftControl, down: true)
        #expect(ledger.reportModifiers == HIDModifier.leftControl.bit)
        ledger.observe(deviceID: 1, modifier: .leftControl, down: false)
        #expect(ledger.heldPhysicalModifiers == 0)
    }
    @Test func noCaptureBeforeOutputReadyOrDuringSecureInput() {
        var gate = HIDCaptureGate()
        #expect(!gate.maySeize)
        gate.permissionsGranted = true; gate.sessionActive = true; gate.physicalKeysNeutral = true
        #expect(!gate.maySeize)
        gate.virtualKeyboardReady = true
        #expect(!gate.maySeize)
        gate.secureInput = false
        #expect(gate.maySeize)
        gate.virtualKeyboardReady = false
        #expect(!gate.maySeize)
    }
    @Test func unknownDevicesAndCapacityFailClosed() {
        var ledger = HIDModifierLedger()
        #expect(ledger.register(.init(registryID: 50, builtIn: false, vendorID: 1, productID: 1)) == false)
        ledger.observe(deviceID: 50, modifier: .leftOption, down: true)
        #expect(ledger.reportModifiers == 0)
        for id in 0..<HIDModifierLedger.capacity {
            #expect(ledger.register(.init(registryID: UInt64(id), builtIn: true, vendorID: 0, productID: 0)) == true)
        }
        #expect(ledger.register(.init(registryID: 99, builtIn: true, vendorID: 0, productID: 0)) == false)
    }
}
