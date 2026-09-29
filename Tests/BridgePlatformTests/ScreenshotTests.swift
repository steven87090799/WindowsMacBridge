import AppKit
import Foundation
import Testing
import BridgeCore
import BridgePlatform

struct ScreenshotShortcutTests {
    private func nativeEvent(isDown: Bool) throws -> CGEvent {
        let source = try #require(CGEventSource(stateID: .privateState))
        return try #require(CGEvent(keyboardEventSource: source, virtualKey: 1, keyDown: isDown))
    }

    @Test func exactShortcutClaimsOneBalancedPair() {
        var shortcut = ScreenshotShortcut()
        #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: false,
                                command: true, shift: true, option: false, control: false) == .capture)
        #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: true,
                                command: true, shift: true, option: false, control: false) == .suppress)
        #expect(shortcut.handle(keyCode: 1, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .suppress)
        #expect(shortcut.handle(keyCode: 1, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .passThrough)
    }

    @Test func otherChordsAndResetPassThrough() {
        var shortcut = ScreenshotShortcut()
        for (key, command, shift, option, control) in [
            (UInt16(21), true, true, false, false),
            (UInt16(1), false, true, false, false),
            (UInt16(1), true, false, false, false),
            (UInt16(1), true, true, true, false),
            (UInt16(1), true, true, false, true)
        ] {
            #expect(shortcut.handle(keyCode: key, isDown: true, isRepeat: false,
                                    command: command, shift: shift, option: option, control: control) == .passThrough)
        }
        #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: false,
                                command: true, shift: true, option: false, control: false) == .capture)
        shortcut.reset()
        #expect(shortcut.handle(keyCode: 1, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .passThrough)
    }

    @Test func missedReleaseCanRecoverOnFreshDown() {
        var shortcut = ScreenshotShortcut()
        for _ in 0..<2 {
            #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: false,
                                    command: true, shift: true, option: false, control: false) == .capture)
        }
    }

    @Test func thirtyDayScheduleUsesPersistentTimestamp() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: nil, now: now) == ScreenshotCheckSchedule.interval)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: now.addingTimeInterval(-10), now: now) == ScreenshotCheckSchedule.interval - 10)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: now.addingTimeInterval(-ScreenshotCheckSchedule.interval - 1), now: now) == 1)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: now.addingTimeInterval(100), now: now) == ScreenshotCheckSchedule.interval)
    }

    @Test func translatedControlShiftSaveNeverStartsScreenshot() throws {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: .max, bundleID: "test.privateSave", mode: .macOS),
                            enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                     modifierSide: .leftControl, modifierDown: true))
        _ = processor.process(.init(.flagsChanged, keyCode: 56, modifiers: [.control, .shift],
                                     modifierSide: .leftShift, modifierDown: true))
        var shortcut = ScreenshotShortcut()
        for (phase, repeatKey) in [(KeyPhase.down, false), (.down, true), (.up, false)] {
            let decision = processor.process(.init(phase, keyCode: 1, modifiers: [.control, .shift],
                                                   isRepeat: repeatKey))
            guard case let .rewrite(key, modifiers, rule) = decision else {
                Issue.record("Save As translation must remain available: \(decision)")
                return
            }
            #expect(rule == "karabiner.20")
            let event = try nativeEvent(isDown: phase == .down)
            event.flags = [.maskControl, .maskShift]
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            EventRewriter.apply(to: event, keyCode: key, modifiers: modifiers,
                                marker: EventRewriter.generatedEventMarker)
            #expect(InputEngine.modifiers(event.flags) == [.command, .shift])
            // Reproduce the production order: Windows translation precedes the screenshot tap.
            #expect(shortcut.handle(type: event.type, event: event) == .passThrough)
        }
        #expect(processor.activePressCount == 0)
    }

    @Test func nativeWinAndControlChordsWorkWithEitherTapOrder() throws {
        for screenshotFirst in [false, true] {
            for useControl in [false, true] {
                var processor = KeyboardEventProcessor()
                processor.configure(context: .init(processID: .max, bundleID: "test.tapOrder", mode: .macOS),
                                    enabled: true, layoutSupported: true)
                processor.reconcileNeutralHardware()
                let modifier: Modifiers = useControl ? .control : .command
                _ = processor.process(.init(.flagsChanged, keyCode: useControl ? 59 : 55, modifiers: modifier,
                                             modifierSide: useControl ? .leftControl : .leftCommand, modifierDown: true))
                _ = processor.process(.init(.flagsChanged, keyCode: 56, modifiers: [modifier, .shift],
                                             modifierSide: .leftShift, modifierDown: true))
                var shortcut = ScreenshotShortcut()
                for phase in [KeyPhase.down, .up] {
                    let event = try nativeEvent(isDown: phase == .down)
                    event.flags = useControl ? [.maskControl, .maskShift] : [.maskCommand, .maskShift]
                    // Actual macOS modifier flags, not the key legends or a synthetic Ctrl alias.
                    #expect(event.getIntegerValueField(.eventSourceUserData) == 0)
                    if screenshotFirst {
                        let screenshotDecision = shortcut.handle(type: event.type, event: event)
                        #expect(screenshotDecision == (useControl ? .passThrough : (phase == .down ? .capture : .suppress)))
                        if screenshotDecision != .passThrough { continue }
                    }
                    let decision = processor.process(.init(phase, keyCode: 1, modifiers: [modifier, .shift]))
                    if useControl {
                        guard case let .rewrite(key, output, rule) = decision else {
                            Issue.record("Ctrl Save As must still translate: \(decision)")
                            return
                        }
                        #expect(rule == "karabiner.20")
                        EventRewriter.apply(to: event, keyCode: key, modifiers: output,
                                            marker: EventRewriter.generatedEventMarker)
                        #expect(InputEngine.modifiers(event.flags) == [.command, .shift])
                    } else { #expect(decision == .passThrough) }
                    if !screenshotFirst {
                        #expect(shortcut.handle(type: event.type, event: event) ==
                                (useControl ? .passThrough : (phase == .down ? .capture : .suppress)))
                    }
                }
                #expect(processor.activePressCount == 0)
            }
        }
    }

    @Test func generatedEventsCannotReleaseOrRepeatAnOriginalScreenshotPress() throws {
        var shortcut = ScreenshotShortcut()
        let down = try nativeEvent(isDown: true)
        down.flags = [.maskCommand, .maskShift]
        #expect(down.getIntegerValueField(.eventSourceUserData) == 0)
        #expect(shortcut.handle(type: .keyDown, event: down) == .capture)
        let ownUp = try nativeEvent(isDown: false)
        EventRewriter.apply(to: ownUp, keyCode: 1, modifiers: [.command, .shift],
                            marker: EventRewriter.generatedEventMarker)
        #expect(shortcut.handle(type: .keyUp, event: ownUp) == .passThrough)
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(shortcut.handle(type: .keyDown, event: down) == .suppress)
        let up = try nativeEvent(isDown: false)
        up.flags = [] // Modifiers released before the original S key.
        #expect(shortcut.handle(type: .keyUp, event: up) == .suppress)
        #expect(shortcut.handle(type: .keyUp, event: up) == .passThrough)
        // Another source's nonzero metadata is not our marker and remains eligible.
        let foreignDown = try nativeEvent(isDown: true)
        foreignDown.flags = [.maskCommand, .maskShift]
        foreignDown.setIntegerValueField(.eventSourceUserData, value: -1)
        #expect(shortcut.handle(type: .keyDown, event: foreignDown) == .capture)
    }
}

@MainActor struct ScreenshotClipboardTests {
    @Test func savedImageCopiesAsImageAndMissingFileIsRejected() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeScreenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let data = try #require(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        try data.write(to: path)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("BridgeScreenshot-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ScreenshotClipboard.copyImage(at: path, to: pasteboard) == .success)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) == data)
        #expect(NSImage(pasteboard: pasteboard) != nil)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) != nil)
        #expect(pasteboard.data(forType: .tiff) != nil)
        let changeCount = pasteboard.changeCount
        #expect(ScreenshotClipboard.copyImage(at: path.appendingPathExtension("missing"), to: pasteboard) == .unreadableImage)
        #expect(pasteboard.changeCount == changeCount)
    }

    @Test func jpegScreenshotIsConvertedToPasteablePNG() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeScreenshot-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: path) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                      bitsPerPixel: 0)
        try #require(bitmap?.representation(using: .jpeg, properties: [:])).write(to: path)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("BridgeScreenshot-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ScreenshotClipboard.copyImage(at: path, to: pasteboard) == .success)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) != nil)
    }

    @Test func backgroundImagePreparationPublishesOnlyImmutableImageData() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeWorker-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let original = try #require(bitmap.representation(using: .png, properties: [:]))
        try original.write(to: path)
        let payload = try #require(await Task.detached { ScreenshotImagePreparation.prepare(at: path) }.value)
        let pasteboard = NSPasteboard(name: .init("BridgeWorker-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ScreenshotClipboard.write(payload, to: pasteboard) == .success)
        #expect(pasteboard.data(forType: .init("public.png")) == original)
        #expect(NSImage(pasteboard: pasteboard) != nil)
    }
}
