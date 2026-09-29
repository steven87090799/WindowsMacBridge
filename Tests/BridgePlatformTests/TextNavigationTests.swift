import AppKit
import Testing
import BridgeCore
@testable import BridgePlatform

/// Private, never-shown text window: no global events or clipboard operations.
@MainActor struct TextNavigationTests {
    private let content = "one two three\nfour five six"

    private func apply(_ key: UInt16, modifiers: Modifiers, at position: Int) throws -> NSTextView {
        _ = NSApplication.shared
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: .max, bundleID: "test.privateText", mode: .macOS),
                            enabled: true, layoutSupported: true, textNavigationEnabled: true)
        processor.reconcileNeutralHardware()
        var held: Modifiers = []
        for (group, side, code) in [(Modifiers.control, ModifierSide.leftControl, UInt16(59)),
                                    (.shift, .leftShift, 56)] where modifiers.contains(group) {
            held.insert(group)
            _ = processor.process(.init(.flagsChanged, keyCode: code, modifiers: held,
                                         modifierSide: side, modifierDown: true))
        }
        let result = processor.process(.init(.down, keyCode: key, modifiers: modifiers))
        guard case let .rewrite(outputKey, outputModifiers, _) = result else {
            Issue.record("Expected a translated text command: \(result)")
            throw CocoaError(.featureUnsupported)
        }
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true))
        EventRewriter.apply(to: event, keyCode: outputKey, modifiers: outputModifiers, marker: 123)
        let native = try #require(NSEvent(cgEvent: event))
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        view.isRichText = false
        view.string = content
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: position, length: 0))
        // CGEvent conversion has no window number. Route the translated event
        // to this private text responder, without global delivery or activation.
        let scopedEvent = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: native.modifierFlags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: native.characters ?? "", charactersIgnoringModifiers: native.charactersIgnoringModifiers ?? "",
            isARepeat: false, keyCode: native.keyCode))
        view.keyDown(with: scopedEvent)
        return view
    }

    @Test func wordMovementAndShiftSelectionsUseNativeTextBehavior() throws {
        #expect(try apply(123, modifiers: .control, at: 8).selectedRange() == NSRange(location: 4, length: 0))
        #expect(try apply(124, modifiers: .control, at: 4).selectedRange() == NSRange(location: 7, length: 0))
        #expect(try apply(123, modifiers: [.control, .shift], at: 8).selectedRange() == NSRange(location: 4, length: 4))
        #expect(try apply(124, modifiers: [.control, .shift], at: 4).selectedRange() == NSRange(location: 4, length: 3))
    }
    @Test func wordDeletionRemovesOnlyTheExpectedWord() throws {
        #expect(try apply(51, modifiers: .control, at: 8).string == "one three\nfour five six")
        #expect(try apply(117, modifiers: .control, at: 4).string == "one  three\nfour five six")
    }
    @Test func homeEndAndShiftSelectionsStayWithinTheLine() throws {
        #expect(try apply(115, modifiers: [], at: 16).selectedRange() == NSRange(location: 14, length: 0))
        #expect(try apply(119, modifiers: [], at: 16).selectedRange() == NSRange(location: 27, length: 0))
        #expect(try apply(115, modifiers: .shift, at: 16).selectedRange() == NSRange(location: 14, length: 2))
        #expect(try apply(119, modifiers: .shift, at: 16).selectedRange() == NSRange(location: 16, length: 11))
    }
    @Test func controlHomeEndAndShiftSelectionsReachDocumentBoundaries() throws {
        #expect(try apply(115, modifiers: .control, at: 16).selectedRange() == NSRange(location: 0, length: 0))
        #expect(try apply(119, modifiers: .control, at: 16).selectedRange() == NSRange(location: 27, length: 0))
        #expect(try apply(115, modifiers: [.control, .shift], at: 16).selectedRange() == NSRange(location: 0, length: 16))
        #expect(try apply(119, modifiers: [.control, .shift], at: 16).selectedRange() == NSRange(location: 16, length: 11))
    }
}
