import Testing
import BridgeCore

struct ShortcutPreviewTests {
    private func configuration(_ mode: ApplicationMode = .macOS, bundle: String = "test.local") -> ShortcutPreviewConfiguration {
        var value = ShortcutPreviewConfiguration()
        value.context = .init(processID: 10, bundleID: bundle, mode: mode)
        return value
    }
    @Test func terminalAndIDEKeepTheirActualClipboardAndInterruptRules() {
        for mode: ApplicationMode in [.macOS, .terminal, .ide] {
            let value = configuration(mode)
            for (input, output): (UInt16, UInt16) in [(8,8),(9,9),(0,0),(7,7)] {
                let result = ShortcutPreview.evaluate(.init(keyCode: input, modifiers: .control), configuration: value)
                if mode == .terminal && input == 8 {
                    #expect(result.decision == .action(.terminalCopyOrInterrupt, ruleID: "terminal.copyOrInterrupt"))
                    #expect(result.output.contains("有選取") && result.output.contains("中斷命令"))
                    continue
                }
                #expect(result.decision == .rewrite(keyCode: output, modifiers: .command,
                    ruleID: [8:"windows.copy",9:"windows.paste",0:"windows.selectAll",7:"windows.cut"][input]!))
            }
        }
        let interrupt = ShortcutPreview.evaluate(.init(keyCode: 8, modifiers: [.control,.shift]), configuration: configuration(.terminal))
        #expect(interrupt.decision == .rewrite(keyCode: 8, modifiers: .control, ruleID: "terminal.interrupt"))
        #expect(ShortcutPreview.evaluate(.init(keyCode: 1, modifiers: .control), configuration: configuration(.ide)).decision ==
            .rewrite(keyCode: 1, modifiers: .command, ruleID: "windows.save"))
    }
    @Test func protectedAppsAndDisabledPreviewNeverTranslate() {
        for mode: ApplicationMode in [.remoteWindows,.virtualMachine,.game,.disabled] {
            for chord in ShortcutPreview.samples(windowsKey: .command) {
                #expect(ShortcutPreview.evaluate(chord, configuration: configuration(mode)).decision == .passThrough)
            }
        }
        var disabled = configuration(); disabled.enabled = false
        for chord in ShortcutPreview.samples(windowsKey: .command) {
            #expect(ShortcutPreview.evaluate(chord, configuration: disabled).decision == .passThrough)
        }
    }
    @Test func screenshotInterceptorAlsoAppliesInTerminalAndDoesNotDependOnTextLayout() {
        for mode: ApplicationMode in [.macOS,.terminal,.ide] {
            var value = configuration(mode); value.layoutSupported = false
            let chord = Shortcut(keyCode: 1, modifiers: [.command,.shift])
            #expect(ShortcutPreview.evaluate(chord, configuration: value).decision == .action(.screenshot(.region), ruleID: "windows.screenshot"))
            value.screenshotEnabled = false
            #expect(ShortcutPreview.evaluate(chord, configuration: value).decision == .passThrough)
        }
    }
    @Test func finderAndBrowserUseTheSelectedAppAndFeatureFlags() {
        var finder = configuration(bundle: "com.apple.finder")
        let delete = Shortcut(keyCode: 117, modifiers: .shift)
        #expect(ShortcutPreview.evaluate(delete, configuration: finder).decision == .action(.finder(.permanentDelete), ruleID: "finder.permanentDelete"))
        finder.finderPermanentDeleteEnabled = false
        #expect(ShortcutPreview.evaluate(delete, configuration: finder).decision == .passThrough)
        var browser = configuration(); browser.context.isBrowser = true
        #expect(ShortcutPreview.evaluate(.init(keyCode: 17, modifiers: .control), configuration: browser).decision ==
            .rewrite(keyCode: 17, modifiers: .command, ruleID: "karabiner.42"))
    }
    @Test func remotePreviewDoesNotDoubleTranslateOrGuessUnknownSources() {
        var value = configuration()
        let chord = Shortcut(keyCode: 8, modifiers: .control)
        value.source = .remoteWindows
        #expect(ShortcutPreview.evaluate(chord, configuration: value).decision == .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
        for source: ShortcutPreviewSource in [.remoteMac,.remoteAutomatic] {
            value.source = source
            #expect(ShortcutPreview.evaluate(chord, configuration: value).decision == .passThrough)
        }
    }
    @Test func allGeneralRulesMatchTheirActualCompiledOutput() {
        let value = configuration()
        for rule in WindowsCompatibilityRules.general {
            #expect(ShortcutPreview.evaluate(rule.input, configuration: value).decision ==
                .rewrite(keyCode: rule.output.keyCode, modifiers: rule.output.modifiers, ruleID: rule.id))
        }
        #expect(Set(ShortcutPreview.samples(windowsKey: .command)).count == ShortcutPreview.samples(windowsKey: .command).count)
    }
}
