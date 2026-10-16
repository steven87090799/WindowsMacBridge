import Testing
@testable import BridgeCore

struct FullLocalWindowsProfileTests {
    @Test func terminalAndIDEAllowHIDWindowScreenshotAndSystemActions() {
        for mode: ApplicationMode in [.terminal, .ide] {
            var engine = HIDTranslationEngine(); _ = engine.register(1)
            engine.configure(context: .init(processID: 10, bundleID: "test.local", mode: mode),
                layoutSupported: true, finderEnabled: false, altF4Enabled: true, screenshotEnabled: true)
            _ = engine.observe(device: 1, page: 7, usage: 0xe3, down: true)
            #expect(engine.observe(device: 1, page: 7, usage: 0x3d, down: true) == .window(.close))
            _ = engine.observe(device: 1, page: 7, usage: 0x3d, down: false)
            _ = engine.observe(device: 1, page: 7, usage: 0xe3, down: false)
            #expect(engine.observe(device: 1, page: 7, usage: 0x46, down: true) == .screenshot(.region))
            _ = engine.observe(device: 1, page: 7, usage: 0x46, down: false)
            _ = engine.observe(device: 1, page: 7, usage: 0xe2, down: true)
            #expect(engine.observe(device: 1, page: 7, usage: 8, down: true) == .system(.openFinder))
            _ = engine.observe(device: 1, page: 7, usage: 8, down: false)
            _ = engine.observe(device: 1, page: 7, usage: 0xe2, down: false)
            var report = HIDOutput(); let rendered = engine.render(into: &report)
            #expect(rendered && report.isEmpty)
        }
    }
    @Test func terminalAndIDETranslateSaveUndoRedoTabsAndWordNavigationOnBothBackends() {
        let cases: [(key: UInt16, usage: UInt16, outputKey: UInt16, outputUsage: UInt16, flags: Modifiers, hidFlags: UInt8)] = [
            (1,0x16,1,0x16,.command,8), (6,0x1d,6,0x1d,.command,8),
            (16,0x1c,6,0x1d,[.command,.shift],10), (17,0x17,17,0x17,.command,8),
            (3,0x09,3,0x09,.command,8), (13,0x1a,13,0x1a,.command,8),
            (123,0x50,123,0x50,.option,4)
        ]
        for mode: ApplicationMode in [.terminal,.ide] {
            for item in cases {
                let context = ApplicationContext(processID: 10, bundleID: "test.local", mode: mode)
                var p = KeyboardEventProcessor()
                p.configure(context: context, enabled: true, layoutSupported: true)
                p.reconcileNeutralHardware()
                p.reconcileIndependentSourceFlags(.control)
                let down = p.process(.init(.down, keyCode: item.key, modifiers: .control))
                guard case .rewrite(let key, let flags, _) = down else { Issue.record("Expected Windows rewrite for \(mode), key \(item.key)"); continue }
                #expect(key == item.outputKey && flags == item.flags)
                #expect(p.process(.init(.up, keyCode: item.key, modifiers: .control)) == down)
                #expect(p.activePressCount == 0)

                var hid = HIDTranslationEngine(); _ = hid.register(1)
                hid.configure(context: context, layoutSupported: true, finderEnabled: false)
                _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: true)
                _ = hid.observe(device: 1, page: 7, usage: item.usage, down: true)
                var report = HIDOutput(); let rendered = hid.render(into: &report); #expect(rendered)
                #expect(report.modifiers == item.hidFlags && report.keys[0] == item.outputUsage)
                _ = hid.observe(device: 1, page: 7, usage: item.usage, down: false)
                let keyReleased = hid.render(into: &report)
                #expect(keyReleased && report.keyCount == 0 && report.modifiers == 1)
                _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: false)
                let controlReleased = hid.render(into: &report)
                #expect(controlReleased && report.keyCount == 0 && report.modifiers == 0)
            }
        }
    }
}
