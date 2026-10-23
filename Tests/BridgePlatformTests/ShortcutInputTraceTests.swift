import CoreGraphics
import Testing
import BridgeCore
@testable import BridgePlatform

struct ShortcutInputTraceTests {
    @Test func traceAllowsOnlyClipboardChordsAndControlFnEdges() {
        for key: UInt16 in [0, 7, 8, 9] {
            for flags: Modifiers in [.control, .command, .fn] {
                #expect(InputEngine.tracesShortcutInput(type: .keyDown, key: key, flags: flags, isRepeat: false))
            }
            #expect(!InputEngine.tracesShortcutInput(type: .keyDown, key: key, flags: [], isRepeat: false))
            #expect(!InputEngine.tracesShortcutInput(type: .keyDown, key: key, flags: .shift, isRepeat: false))
            #expect(!InputEngine.tracesShortcutInput(type: .keyDown, key: key, flags: .control, isRepeat: true))
            #expect(!InputEngine.tracesShortcutInput(type: .keyUp, key: key, flags: .control, isRepeat: false))
        }
        for key in UInt16(0)..<128 {
            #expect(InputEngine.tracesShortcutInput(type: .flagsChanged, key: key, flags: [], isRepeat: false) == [59, 62, 63].contains(key))
            if ![0, 7, 8, 9].contains(key) {
                #expect(!InputEngine.tracesShortcutInput(type: .keyDown, key: key, flags: [.control, .fn], isRepeat: false))
            }
        }
    }
}
