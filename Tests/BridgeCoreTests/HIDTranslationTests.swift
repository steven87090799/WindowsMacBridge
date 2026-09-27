import Testing
import BridgeCore

struct HIDTranslationTests {
    @Test func remoteVMGameAndUnknownLayoutHandBackPhysicalDevices() {
        for mode: ApplicationMode in [.remoteWindows,.virtualMachine,.game,.disabled] {
            #expect(HIDCapturePolicy.requiresNativePassThrough(mode: mode, layoutSupported: true))
        }
        for mode: ApplicationMode in [.macOS,.terminal,.ide] {
            #expect(!HIDCapturePolicy.requiresNativePassThrough(mode: mode, layoutSupported: true))
            #expect(HIDCapturePolicy.requiresNativePassThrough(mode: mode, layoutSupported: false))
        }
    }
    @Test func everyGeneralAndBrowserRuleProducesItsCompiledHIDOutput() {
        for (rules, browser) in [(WindowsCompatibilityRules.general, false), (WindowsCompatibilityRules.browser, true)] {
            for rule in rules {
                var e = engine(browser: browser)
                for (flag, usage): (Modifiers, UInt16) in [(.control,0xe0),(.command,0xe3),(.option,0xe2),(.shift,0xe1)] {
                    if rule.input.modifiers.contains(flag) { _ = e.observe(device: 1, page: 7, usage: usage, down: true) }
                }
                guard let input = HIDKeyMap.usage[Int(rule.input.keyCode)], let expected = HIDKeyMap.usage[Int(rule.output.keyCode)] else { Issue.record("Missing key map for \(rule.id)"); continue }
                _ = e.observe(device: 1, page: 7, usage: input, down: true)
                let out = output(&e)
                #expect(out.keyCount == 1); #expect(out.keys[0] == expected)
                var flags: UInt8 = 0
                if rule.output.modifiers.contains(.control) { flags |= 1 }
                if rule.output.modifiers.contains(.command) { flags |= 8 }
                if rule.output.modifiers.contains(.option) { flags |= 4 }
                if rule.output.modifiers.contains(.shift) { flags |= 2 }
                #expect(out.modifiers == flags); #expect(!out.fn)
            }
        }
    }
    private func engine(_ mode: ApplicationMode = .macOS, browser: Bool = false) -> HIDTranslationEngine {
        var e = HIDTranslationEngine(); _ = e.register(1); _ = e.register(2)
        e.configure(context: .init(processID: 10, bundleID: "test", mode: mode, isBrowser: browser), layoutSupported: true, finderEnabled: true)
        return e
    }
    private func output(_ e: inout HIDTranslationEngine) -> HIDOutput {
        var out = HIDOutput(); let ok = e.render(into: &out); #expect(ok); return out
    }
    @Test func physicalControlCopyConsumesSwappedFnAndPairsRelease() {
        var e = engine()
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        #expect(output(&e).fn)
        _ = e.observe(device: 1, page: 7, usage: 6, down: true)
        let down = output(&e); #expect(!down.fn); #expect(down.modifiers == 8); #expect(down.keys[0] == 6)
        _ = e.observe(device: 1, page: 7, usage: 6, down: false)
        #expect(output(&e).isEmpty)
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: false)
        #expect(output(&e).isEmpty)
    }
    @Test func altTabKeepsCommandUntilAltRelease() {
        var e = engine()
        _ = e.observe(device: 1, page: 7, usage: 0xe2, down: true)
        for _ in 0..<4 {
            _ = e.observe(device: 1, page: 7, usage: 0x2b, down: true)
            #expect(output(&e).modifiers == 8)
            _ = e.observe(device: 1, page: 7, usage: 0x2b, down: false)
            #expect(output(&e).modifiers == 8)
        }
        _ = e.observe(device: 1, page: 7, usage: 0xe2, down: false)
        #expect(output(&e).isEmpty)
    }
    @Test func protectedProfilesPreserveCtrlFnAltAndBrightness() {
        for mode: ApplicationMode in [.terminal,.remoteWindows,.virtualMachine,.game,.ide,.disabled] {
            var e = engine(mode)
            _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
            _ = e.observe(device: 1, page: 7, usage: 6, down: true)
            let out = output(&e); #expect(out.modifiers == 1); #expect(!out.fn); #expect(out.keys[0] == 6)
            _ = e.observe(device: 1, page: 0x0c, usage: 0x6f, down: true)
            #expect(output(&e).consumerCount == 1)
        }
    }
    @Test func transitionWhileHeldDoesNotMigrateIntoRemote() {
        var e = engine()
        _ = e.observe(device: 1, page: 7, usage: 0xe2, down: true)
        _ = e.observe(device: 1, page: 7, usage: 0x2b, down: true)
        e.configure(context: .init(processID: 20, mode: .remoteWindows), layoutSupported: true, finderEnabled: false)
        #expect(output(&e).isEmpty)
        _ = e.observe(device: 1, page: 7, usage: 4, down: true)
        #expect(output(&e).isEmpty)
        for usage: UInt16 in [4,0x2b,0xe2] { _ = e.observe(device: 1, page: 7, usage: usage, down: false) }
        _ = e.observe(device: 1, page: 7, usage: 0xe2, down: true)
        #expect(output(&e).modifiers == 4)
    }
    @Test func disconnectDoesNotReleaseOtherKeyboardOwners() {
        var e = engine()
        for device: UInt64 in [1,2] {
            _ = e.observe(device: device, page: 7, usage: 0xe2, down: true)
            _ = e.observe(device: device, page: 7, usage: 4, down: true)
        }
        e.disconnect(1)
        let out = output(&e); #expect(out.keyCount == 1); #expect(out.modifiers == 8)
        e.disconnect(2); #expect(output(&e).isEmpty)
    }
    @Test func brightnessAndManualToggleArePairedWithoutRecursion() {
        var e = engine()
        _ = e.observe(device: 1, page: 0x0c, usage: 0x6f, down: true)
        #expect(output(&e).keys[0] == 0x28)
        _ = e.observe(device: 1, page: 0x0c, usage: 0x6f, down: false)
        _ = e.observe(device: 1, page: 7, usage: 0xe6, down: true)
        _ = e.observe(device: 1, page: 7, usage: 0x13, down: true)
        #expect(e.manualPassThrough); #expect(output(&e).isEmpty)
        _ = e.observe(device: 1, page: 7, usage: 0x13, down: false)
        _ = e.observe(device: 1, page: 7, usage: 0xe6, down: false)
        _ = e.observe(device: 1, page: 0x0c, usage: 0x6f, down: true)
        #expect(output(&e).consumerCount == 1)
    }
    @Test func finderActionIsOnceAndOutputDoesNotHoldModifiers() {
        var e = engine()
        e.configure(context: .init(processID: 10, bundleID: "com.apple.finder", mode: .macOS), layoutSupported: true, finderEnabled: true)
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        let first = e.observe(device: 1, page: 7, usage: 0x1b, down: true)
        #expect(first == .finder(.cut)); #expect(output(&e).isEmpty)
        let duplicate = e.observe(device: 1, page: 7, usage: 0x1b, down: true)
        #expect(duplicate == nil)
    }
    @Test func stressOneHundredTwentyThousandEvents() {
        var e = engine(browser: true); var out = HIDOutput()
        for i in 0..<30_000 {
            let usage: UInt16 = i % 2 == 0 ? 6 : 0x17
            _ = e.observe(device: 1, page: 7, usage: 0xe4, down: true)
            _ = e.observe(device: 1, page: 7, usage: usage, down: true)
            let ok = e.render(into: &out); #expect(ok); #expect(out.modifiers == 8)
            _ = e.observe(device: 1, page: 7, usage: usage, down: false)
            _ = e.observe(device: 1, page: 7, usage: 0xe4, down: false)
        }
        #expect(output(&e).isEmpty); #expect(e.processed == 120_000); #expect(!e.faulted)
    }
}
