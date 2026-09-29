import AppKit
import Foundation
import Testing
import BridgePlatform

struct ScreenshotShortcutTests {
    @Test func exactShortcutClaimsOneBalancedPair() {
        var shortcut = ScreenshotShortcut()
        #expect(shortcut.handle(keyCode: 21, isDown: true, isRepeat: false,
                                command: true, shift: true, option: false, control: false) == .capture)
        #expect(shortcut.handle(keyCode: 21, isDown: true, isRepeat: true,
                                command: true, shift: true, option: false, control: false) == .suppress)
        #expect(shortcut.handle(keyCode: 21, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .suppress)
        #expect(shortcut.handle(keyCode: 21, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .passThrough)
    }

    @Test func otherChordsAndResetPassThrough() {
        var shortcut = ScreenshotShortcut()
        for (key, command, shift, option, control) in [
            (UInt16(20), true, true, false, false),
            (UInt16(21), false, true, false, false),
            (UInt16(21), true, false, false, false),
            (UInt16(21), true, true, true, false),
            (UInt16(21), true, true, false, true)
        ] {
            #expect(shortcut.handle(keyCode: key, isDown: true, isRepeat: false,
                                    command: command, shift: shift, option: option, control: control) == .passThrough)
        }
        #expect(shortcut.handle(keyCode: 21, isDown: true, isRepeat: false,
                                command: true, shift: true, option: false, control: false) == .capture)
        shortcut.reset()
        #expect(shortcut.handle(keyCode: 21, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .passThrough)
    }

    @Test func missedReleaseCanRecoverOnFreshDown() {
        var shortcut = ScreenshotShortcut()
        for _ in 0..<2 {
            #expect(shortcut.handle(keyCode: 21, isDown: true, isRepeat: false,
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
        #expect(NSImage(pasteboard: pasteboard) != nil)
        #expect(ScreenshotClipboard.copyImage(at: path.appendingPathExtension("missing"), to: pasteboard) == .unreadableImage)
    }
}
