import Testing
@testable import BridgeCore

struct DestinationSemanticsTests {
    @Test func denyingHelperActionsPreservesOriginalPairsInsteadOfSwallowingLegacyChords() {
        for usage: UInt16 in [0x1b, 0x46] {
            var hid = HIDTranslationEngine(); _ = hid.register(1)
            hid.configure(context: .init(processID: 1, bundleID: "com.apple.finder", mode: .macOS),
                layoutSupported: true, finderEnabled: true, screenshotEnabled: true, actionsEnabled: false)
            _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: true)
            let action = hid.observe(device: 1, page: 7, usage: usage, down: true)
            var out = HIDOutput(); let first = hid.render(into: &out)
            #expect(action == nil && first && out.modifiers == 1 && out.keys.prefix(out.keyCount).contains(usage))
            _ = hid.observe(device: 1, page: 7, usage: usage, down: false)
            let released = hid.render(into: &out)
            #expect(released && out.modifiers == 1 && out.keyCount == 0)
        }
    }
    @Test func globalWindowsChordsAreEncodedInHIDBeforeWindowServerCanStealWinTab() {
        for modifier in WindowsKeyModifier.allCases {
            for (key, output, flags): (UInt16, UInt16, UInt8) in [(0x2b,0x52,1), (0x15,0x2c,8), (0x0f,0x14,9)] {
                var hid = HIDTranslationEngine(); _ = hid.register(1)
                hid.configure(context: .init(processID: 1, bundleID: "com.apple.finder", mode: .macOS),
                    layoutSupported: true, finderEnabled: true, windowsKeyModifier: modifier,
                    winRunEnabled: true, winTaskViewEnabled: true, transportOnly: true)
                let win: UInt16 = modifier == .command ? 0xe3 : 0xe2
                _ = hid.observe(device: 1, page: 7, usage: win, down: true)
                let action = hid.observe(device: 1, page: 7, usage: key, down: true)
                #expect(action == nil)
                var out = HIDOutput(); let first = hid.render(into: &out); #expect(first)
                #expect(out.modifiers == flags && out.keys.prefix(out.keyCount).contains(output))
                _ = hid.observe(device: 1, page: 7, usage: key, down: false)
                let released = hid.render(into: &out); #expect(released)
                #expect(out.modifiers == (modifier == .command ? 8 : 4) && out.keyCount == 0)
            }
        }
    }
    @Test func sourceFinderCannotExecuteActionOrSuppressAKeyForTheOtherMac() {
        var hid = HIDTranslationEngine(); _ = hid.register(1)
        hid.configure(context: .init(processID: 1, bundleID: "com.apple.finder", mode: .macOS),
                      layoutSupported: true, finderEnabled: true, altF4Enabled: true,
                      windowsKeyModifier: .command, screenshotEnabled: true, transportOnly: true)
        _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: true)
        let cut = hid.observe(device: 1, page: 7, usage: 0x1b, down: true)
        var out = HIDOutput(); let rendered = hid.render(into: &out)
        #expect(cut == nil && rendered && out.modifiers == 1 && out.keys.prefix(out.keyCount).contains(0x1b))
    }
    @Test func sourceAppAndLayoutChangesDoNotReleaseRawTransportHolds() {
        var hid = HIDTranslationEngine(); _ = hid.register(1)
        hid.configure(context: .init(processID: 1, bundleID: "com.apple.Terminal", mode: .terminal),
                      layoutSupported: false, finderEnabled: false, transportOnly: true)
        _ = hid.observe(device: 1, page: 7, usage: 0xe0, down: true)
        _ = hid.observe(device: 1, page: 7, usage: 6, down: true)
        hid.configure(context: .init(processID: 2, bundleID: "com.apple.universalcontrol", mode: .macOS),
                      layoutSupported: true, finderEnabled: true, transportOnly: true)
        var out = HIDOutput(); let rendered = hid.render(into: &out)
        #expect(rendered && out.modifiers == 1 && out.keys.prefix(out.keyCount).contains(6))
        hid.invalidate(); _ = hid.render(into: &out)
        #expect(out.isEmpty)
    }
    @Test func onlyAnnotatedDeliveryToThisMacAuthorizesDestinationSemantics() {
        #expect(DestinationSemanticPolicy.acceptsDelivery(target: 17, foreground: 17))
        #expect(!DestinationSemanticPolicy.acceptsDelivery(target: 0, foreground: 17))
        #expect(!DestinationSemanticPolicy.acceptsDelivery(target: 18, foreground: 17))
        #expect(!DestinationSemanticPolicy.acceptsDelivery(target: 17, foreground: 0))
    }
    @Test func globalScreenshotsAcceptMenuRecipientsWithoutChangingAppSemantics() {
        for kind: ScreenshotKind in [.region, .fullScreen, .fullScreenSave] {
            #expect(DestinationSemanticPolicy.acceptsScreenshotDelivery(target: 18, foreground: 17, kind: kind))
            #expect(DestinationSemanticPolicy.acceptsScreenshotDelivery(target: 17, foreground: 17, kind: kind))
        }
        #expect(!DestinationSemanticPolicy.acceptsDelivery(target: 18, foreground: 17))
        #expect(!DestinationSemanticPolicy.acceptsScreenshotDelivery(target: 18, foreground: 17, kind: .activeWindow))
        #expect(DestinationSemanticPolicy.acceptsScreenshotDelivery(target: 17, foreground: 17, kind: .activeWindow))
    }
    @Test func missingLocalDeliveryCannotCaptureTheUniversalControlSourceMac() {
        for kind in ScreenshotKind.allCases {
            for target: Int32 in [0, -1] {
                #expect(!DestinationSemanticPolicy.acceptsScreenshotDelivery(target: target, foreground: 17, kind: kind))
            }
            #expect(!DestinationSemanticPolicy.acceptsScreenshotDelivery(target: 18, foreground: 0, kind: kind))
        }
    }
    @Test func missingRecipientCanOnlyContinueAnAlreadyOwnedNativeTabSession() {
        #expect(!DestinationSemanticPolicy.acceptsKeyDown(target: 0, foreground: 17, key: 8, nativeTabHeld: true))
        #expect(!DestinationSemanticPolicy.acceptsKeyDown(target: 0, foreground: 17, key: 48, nativeTabHeld: false))
        #expect(DestinationSemanticPolicy.acceptsKeyDown(target: 0, foreground: 17, key: 48, nativeTabHeld: true))
        #expect(DestinationSemanticPolicy.acceptsKeyDown(target: 18, foreground: 17, key: 48, nativeTabHeld: true))
        #expect(DestinationSemanticPolicy.acceptsKeyDown(target: 17, foreground: 17, key: 8, nativeTabHeld: false))
    }
    @Test func systemPanelUsesItsOwnRulesOverFinderTerminalOrRemoteWindows() {
        let panel = ApplicationContext(processID: 18, bundleID: "com.apple.screencaptureui", mode: .macOS)
        for mode: ApplicationMode in [.macOS, .terminal, .remoteWindows] {
            let foreground = ApplicationContext(processID: 17, bundleID: "underlying.app", mode: mode)
            let recipient = DestinationSemanticPolicy.context(target: 18, foreground: foreground, recipients: [18: panel])
            #expect(recipient == panel)
            #expect(DestinationSemanticPolicy.acceptsKeyDown(target: 18, foreground: 17, key: 8, nativeTabHeld: false))
            var processor = KeyboardEventProcessor()
            processor.configure(context: recipient!, enabled: true, layoutSupported: true, finderEnabled: true)
            processor.reconcileNeutralHardware()
            _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                modifierSide: .leftControl, modifierDown: true))
            for key: UInt16 in [8, 9, 7, 0, 6, 16, 1] {
                guard case .rewrite = processor.process(.init(.down, keyCode: key, modifiers: .control)) else {
                    Issue.record("A local panel must use native Windows equivalents, never foreground actions"); continue
                }
                _ = processor.process(.init(.up, keyCode: key, modifiers: .control))
            }
        }
    }
    @Test func unrecognizedOrMissingRecipientsCannotBorrowForegroundRules() {
        let foreground = ApplicationContext(processID: 17, bundleID: "com.apple.finder", mode: .macOS)
        #expect(DestinationSemanticPolicy.context(target: 17, foreground: foreground, recipients: [:]) == foreground)
        for target: Int32 in [0, -1] {
            #expect(DestinationSemanticPolicy.context(target: target, foreground: foreground, recipients: [:]) == nil)
        }
        #expect(DestinationSemanticPolicy.context(target: 18, foreground: foreground, recipients: [:])?.clipboardOnly == true)
        let remote = ApplicationContext(processID: 18, bundleID: "com.microsoft.rdc.macos", mode: .remoteWindows)
        #expect(DestinationSemanticPolicy.context(target: 18, foreground: foreground, recipients: [18: remote]) == remote)
    }
    @Test func firstControlCopyInASystemPanelWorksAfterANeutralProtectedApp() {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: 17, mode: .remoteWindows), enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        // Annotated modifier delivery selects the panel before processing the
        // first Control edge. No key was held across the protected boundary.
        processor.configure(context: .init(processID: 18, bundleID: "com.apple.screencaptureui", mode: .macOS),
            enabled: true, layoutSupported: true, preservingModifiersOnAppChange: true)
        _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
            modifierSide: .leftControl, modifierDown: true))
        #expect(processor.process(.init(.down, keyCode: 8, modifiers: .control)) ==
            .rewrite(keyCode: 8, modifiers: .command, ruleID: "windows.copy"))
    }
    @Test func rawTransportSelectsRulesUsingReceivingAppInsteadOfSourceApp() {
        var target = KeyboardEventProcessor()
        target.configure(context: .init(processID: 17, bundleID: "com.apple.TextEdit", mode: .macOS), enabled: true, layoutSupported: true)
        target.reconcileNeutralHardware()
        _ = target.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true))
        #expect(target.process(.init(.down, keyCode: 6, modifiers: .control)) == .rewrite(keyCode: 6, modifiers: .command, ruleID: "windows.undo"))
        target.invalidate(); target.reconcileNeutralHardware()
        target.configure(context: .init(processID: 18, bundleID: "com.apple.Terminal", mode: .terminal), enabled: true, layoutSupported: true)
        _ = target.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true))
        #expect(target.process(.init(.down, keyCode: 6, modifiers: .control)) == .passThrough)
    }
}
