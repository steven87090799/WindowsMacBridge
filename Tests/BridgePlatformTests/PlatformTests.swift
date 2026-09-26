import Testing
import CoreGraphics
import BridgeCore
@testable import BridgePlatform

struct PlatformTests {
    @Test func testRegistryAndExplicitOverrides() throws {
        let registry = try ApplicationRegistry()
        #expect(registry.mode(for: "tv.parsec.www", overrides: [:]) == .remoteWindows)
        #expect(registry.mode(for: "com.microsoft.rdc.macos", overrides: [:]) == .remoteWindows)
        #expect(registry.mode(for: "com.apple.Terminal", overrides: [:]) == .terminal)
        #expect(registry.mode(for: "com.jetbrains.intellij", overrides: [:]) == .ide)
        #expect(registry.mode(for: "com.openai.codex", overrides: [:]) == .ide)
        #expect(registry.mode(for: "com.apple.Safari", overrides: [:]) == .macOS)
        #expect(registry.mode(for: "", overrides: [:]) == .disabled)
        #expect(registry.mode(for: "com.apple.Safari", overrides: ["com.apple.Safari": .remoteWindows]) == .remoteWindows)
    }
    @Test func testFlagRewritePreservesCapsLockAndNumericPadButRemovesControlSides() {
        let input = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlphaShift.rawValue |
                               CGEventFlags.maskNumericPad.rawValue | 0x2001)
        let output = InputEngine.replacingModifiers(input, with: .command)
        #expect(output.contains(.maskAlphaShift))
        #expect(output.contains(.maskNumericPad))
        #expect(output.contains(.maskCommand))
        #expect(!output.contains(.maskControl))
        #expect(output.rawValue & 0x2001 == 0)
    }
    @Test func testModifierRoundTrip() {
        for value in UInt8(0)..<32 {
            let modifiers = Modifiers(rawValue: value)
            #expect(InputEngine.modifiers(InputEngine.replacingModifiers([], with: modifiers)) == modifiers)
        }
    }
}
