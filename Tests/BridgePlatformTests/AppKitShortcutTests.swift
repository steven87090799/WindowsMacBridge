import AppKit
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor private final class ShortcutTarget: NSObject {
    var invocations = 0
    @objc func performTestShortcut(_ sender: Any?) { invocations += 1 }
}

/// These tests use generated events and a private in-process menu.
/// No event tap, global injection, clipboard writes or user keyboard events.
@MainActor struct AppKitShortcutTests {
    @Test func translatedClipboardReplacesControlCharactersWithNativeCommandCharacters() throws {
        for (key, control, letter): (UInt16, UniChar, UniChar) in [(8,3,99),(7,24,120),(9,22,118),(0,1,97)] {
            let e = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true))
            e.flags = .maskControl
            var input = [control]
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &input)
            let output = try #require(EventRewriter.clipboardReplacement(for: e, keyCode: key, modifiers: .command, marker: 123))
            // Under Zhuyin the raw Unicode is a Bopomofo character. AppKit
            // resolves the native Command event to the Latin menu equivalent.
            let native = try #require(NSEvent(cgEvent: output))
            #expect(native.characters?.utf16.map { $0 } == [letter])
        }
    }
    @Test func translatedEventsMatchRealAppKitMenuShortcuts() throws {
        _ = NSApplication.shared
        for (key, character) in [(UInt16(8), "c"), (7, "x"), (9, "v"), (0, "a"),
                                  (6, "z"), (1, "s"), (3, "f"), (35, "p"), (16, "z")] {
            let rule = try #require(RuleEngine.windows.match(keyCode: key, modifiers: .control))
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true))
            event.flags = .maskControl
            if [UInt16(8), 7, 9, 0].contains(key) {
                var control: [UniChar] = [key == 8 ? 3 : key == 7 ? 24 : key == 9 ? 22 : 1]
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &control)
            }
            EventRewriter.apply(to: event, keyCode: rule.output.keyCode, modifiers: rule.output.modifiers, marker: 1234)
            let output = EventRewriter.clipboardReplacement(for: event, keyCode: rule.output.keyCode, modifiers: rule.output.modifiers, marker: 1234) ?? event
            let appKitEvent = try #require(NSEvent(cgEvent: output))
            let target = ShortcutTarget()
            let menu = NSMenu(title: "Test only")
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "Test action", action: #selector(ShortcutTarget.performTestShortcut(_:)), keyEquivalent: character)
            item.keyEquivalentModifierMask = key == 16 ? [.command, .shift] : [.command]
            item.target = target
            menu.addItem(item)
            let handled = menu.performKeyEquivalent(with: appKitEvent)
            #expect(handled, "AppKit must recognize \(rule.id)")
            #expect(target.invocations == 1)
            #expect(event.getIntegerValueField(.eventSourceUserData) == 1234)
        }
    }
    @Test func nativeClipboardReplacementPreservesDeliveryAndKeyPairMetadata() throws {
        for down in [false, true] {
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: down))
            event.flags = [.maskControl, .maskAlphaShift]
            event.timestamp = 123456789
            event.location = .init(x: 21, y: 34)
            event.setIntegerValueField(.eventTargetUnixProcessID, value: 123)
            event.setIntegerValueField(.eventTargetProcessSerialNumber, value: 456)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            event.setIntegerValueField(.keyboardEventKeyboardType, value: 40)
            let output = try #require(EventRewriter.clipboardReplacement(for: event, keyCode: 8,
                modifiers: down ? .command : [], marker: 987))
            #expect(output.type == event.type && output.timestamp == event.timestamp && output.location == event.location)
            for field: CGEventField in [.eventTargetUnixProcessID, .eventTargetProcessSerialNumber,
                                        .keyboardEventAutorepeat, .keyboardEventKeyboardType] {
                #expect(output.getIntegerValueField(field) == event.getIntegerValueField(field))
            }
            #expect(output.flags.contains(.maskAlphaShift))
            #expect(!output.flags.contains(.maskControl))
            #expect(output.flags.contains(.maskCommand) == down)
            #expect(output.getIntegerValueField(.eventSourceUserData) == 987)
        }
    }
    @Test func upAndRepeatMetadataSurviveRewrite() throws {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 16, keyDown: false))
        event.flags = [.maskControl, .maskAlphaShift]
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        EventRewriter.apply(to: event, keyCode: 6, modifiers: [.command, .shift], marker: 4567)
        #expect(event.type == .keyUp)
        #expect(event.getIntegerValueField(.keyboardEventAutorepeat) == 1)
        #expect(event.flags.contains(.maskAlphaShift))
        #expect(event.getIntegerValueField(.keyboardEventKeycode) == 6)
    }
}
