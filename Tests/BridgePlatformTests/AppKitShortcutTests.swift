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
    @Test func translatedEventsMatchRealAppKitMenuShortcuts() throws {
        _ = NSApplication.shared
        for (key, character) in [(UInt16(8), "c"), (7, "x"), (9, "v"), (0, "a"),
                                  (6, "z"), (1, "s"), (3, "f"), (35, "p"), (16, "z")] {
            let rule = try #require(RuleEngine.windows.match(keyCode: key, modifiers: .control))
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true))
            event.flags = .maskControl
            EventRewriter.apply(to: event, keyCode: rule.output.keyCode, modifiers: rule.output.modifiers, marker: 1234)
            let appKitEvent = try #require(NSEvent(cgEvent: event))
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
