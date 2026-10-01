import Testing
import BridgeCore

struct ReleaseInputRegressionTests {
    private func engine() -> HIDTranslationEngine {
        var e = HIDTranslationEngine()
        let first = e.register(1), second = e.register(2)
        #expect(first && second)
        e.configure(context: .init(processID: 10, bundleID: "test", mode: .macOS),
                    layoutSupported: true, finderEnabled: false)
        return e
    }
    private func output(_ e: inout HIDTranslationEngine) -> HIDOutput {
        var o = HIDOutput(); let rendered = e.render(into: &o); #expect(rendered); return o
    }
    @Test func copyThenTabRestoresStillHeldControl() {
        var e = engine()
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 1, page: 7, usage: 6, down: true)
        #expect(output(&e).modifiers == 8)
        _ = e.observe(device: 1, page: 7, usage: 6, down: false)
        _ = e.observe(device: 1, page: 7, usage: 0x2b, down: true)
        let tab = output(&e)
        #expect(tab.modifiers == 1 && tab.keyCount == 1 && tab.keys[0] == 0x2b)
        _ = e.observe(device: 1, page: 7, usage: 0x2b, down: false)
        #expect(output(&e).modifiers == 1)
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: false)
        #expect(output(&e).isEmpty)
    }
    @Test func recycledDeviceSlotCannotInheritAnOldShortcutModifierOwnership() {
        var e = engine()
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 2, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 2, page: 7, usage: 6, down: true)
        #expect(output(&e).modifiers == 8)
        e.disconnect(1)
        let registered = e.register(3); #expect(registered)
        _ = e.observe(device: 3, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 2, page: 7, usage: 0xe0, down: false)
        let retained = output(&e)
        #expect(retained.modifiers == 1 && retained.keyCount == 0)
        _ = e.observe(device: 2, page: 7, usage: 6, down: false)
        _ = e.observe(device: 3, page: 7, usage: 0xe0, down: false)
        #expect(output(&e).isEmpty)
    }
    @Test func overlappingChordsRollOverWithoutModifierUnionOrOldKeyResurrection() {
        for secondDevice: UInt64 in [1, 2] {
            var e = engine()
            _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
            _ = e.observe(device: 1, page: 7, usage: 6, down: true)
            #expect(output(&e).modifiers == 8)
            _ = e.observe(device: secondDevice, page: 7, usage: 0x4f, down: true)
            let arrow = output(&e)
            #expect(arrow.modifiers == 4 && arrow.keyCount == 1 && arrow.keys[0] == 0x4f)
            _ = e.observe(device: secondDevice, page: 7, usage: 0x4f, down: false)
            #expect(output(&e).keyCount == 0)
            _ = e.observe(device: 1, page: 7, usage: 6, down: true) // duplicate is not a new shortcut
            #expect(output(&e).keyCount == 0)
            _ = e.observe(device: 1, page: 7, usage: 6, down: false)
            _ = e.observe(device: 1, page: 7, usage: 0xe0, down: false)
            #expect(output(&e).isEmpty)
        }
    }
    @Test func leftRightControlAndReleaseOrdersStayBalanced() {
        for order: [UInt16] in [[6, 0xe0, 0xe4], [0xe0, 6, 0xe4], [0xe4, 0xe0, 6]] {
            var e = engine()
            for usage: UInt16 in [0xe0, 0xe4, 6] { _ = e.observe(device: 1, page: 7, usage: usage, down: true) }
            for usage in order { _ = e.observe(device: 1, page: 7, usage: usage, down: false); _ = output(&e) }
            #expect(output(&e).isEmpty)
        }
    }
    @Test func policyInvalidationWhileHeldWaitsForNeutral() {
        for _ in 0..<4 { // pause, secure input, backend and session use the same invalidation contract
            var e = engine()
            for usage: UInt16 in [0xe0, 0xe1, 6] { _ = e.observe(device: 1, page: 7, usage: usage, down: true) }
            e.invalidate(); #expect(output(&e).isEmpty)
            _ = e.observe(device: 2, page: 7, usage: 0x2b, down: true)
            #expect(output(&e).isEmpty)
            for usage: UInt16 in [6, 0xe1, 0xe0] { _ = e.observe(device: 1, page: 7, usage: usage, down: false) }
            _ = e.observe(device: 2, page: 7, usage: 0x2b, down: false)
            _ = e.observe(device: 2, page: 7, usage: 0xe0, down: true)
            #expect(output(&e).modifiers == 1)
        }
    }
    @Test func brightnessIsConsumerInOrdinaryAppsAndDisabledFinder() {
        for bundle in ["test.chat", "com.apple.finder"] {
            var e = engine()
            e.configure(context: .init(processID: 10, bundleID: bundle, mode: .macOS),
                        layoutSupported: true, finderEnabled: false)
            _ = e.observe(device: 1, page: 0x0c, usage: 0x6f, down: true)
            let o = output(&e)
            #expect(o.keyCount == 0 && o.consumerCount == 1 && o.consumer[0] == 0x6f)
        }
    }
}

struct EventTapReleaseRegressionTests {
    @Test func policyTransitionReleasesEachTranslatedKeyOnceToItsOriginalProcess() {
        var p = KeyboardEventProcessor()
        p.configure(context: .init(processID: 71, bundleID: "local", mode: .macOS), enabled: true, layoutSupported: true)
        p.reconcileNeutralHardware()
        _ = p.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true))
        _ = p.process(.init(.down, keyCode: 16, modifiers: .control))
        var releases: [(UInt16, Modifiers, Int32)] = []
        p.drainTranslatedReleases { releases.append(($0, $1, $2)) }
        p.drainTranslatedReleases { releases.append(($0, $1, $2)) }
        #expect(releases.count == 1)
        #expect(releases.first?.0 == 6 && releases.first?.1 == [.command, .shift] && releases.first?.2 == 71)
        p.invalidate()
        #expect(p.process(.init(.up, keyCode: 16, modifiers: .control)) == .suppress)
        #expect(p.activePressCount == 0)
    }
    @Test func rapidRepeatedInputRemainsBoundedAcrossDevicesAndReleaseOrders() {
        var e = HIDTranslationEngine(); _ = e.register(1); _ = e.register(2)
        e.configure(context: .init(processID: 1, bundleID: "test", mode: .macOS), layoutSupported: true, finderEnabled: false)
        for n in 0..<10000 {
            let d = UInt64(n % 2 + 1)
            for u: UInt16 in [0xe0, 6, 6] { _ = e.observe(device: d, page: 7, usage: u, down: true) }
            for u: UInt16 in [6, 0xe0, 6] { _ = e.observe(device: d, page: 7, usage: u, down: false) }
        }
        var output = HIDOutput(); let rendered = e.render(into: &output)
        #expect(rendered && output.isEmpty)
    }
}

struct HIDPrintScreenProvenanceTests {
    @Test func physicalF13IsPreservedWhilePhysicalPrintScreenTriggersCapture() {
        var engine = HIDTranslationEngine(); let registered = engine.register(1); #expect(registered)
        engine.configure(context: .init(processID: 1, bundleID: "test", mode: .macOS),
                         layoutSupported: true, finderEnabled: false, screenshotEnabled: true)
        let f13 = engine.observe(device: 1, page: 7, usage: 0x68, down: true)
        #expect(f13 == nil)
        var report = HIDOutput(); let rendered = engine.render(into: &report)
        #expect(rendered && report.keyCount == 1 && report.keys[0] == 0x68)
        _ = engine.observe(device: 1, page: 7, usage: 0x68, down: false)
        let printScreen = engine.observe(device: 1, page: 7, usage: 0x46, down: true)
        #expect(printScreen == .screenshot(.region))
    }
}
