import Testing
@testable import BridgeCore

@Suite struct NativeScreenshotMappingTests {
    @Test func windowsSnippingUsesNativeSaveChordAndKeepsTheReleasePaired() {
        var mapping = NativeScreenshotMapping()
        let press = mapping.handle(key: 1, down: true, repeating: false, modifiers: [.option, .shift],
            windowsKey: .option, printScreen: .snipping, allowed: true)
        #expect(press?.key == 21 && press?.modifiers == [.command, .shift])
        #expect(mapping.handle(key: 1, down: true, repeating: true, modifiers: [.option, .shift],
            windowsKey: .option, printScreen: .snipping, allowed: true)?.suppress == true)
        let release = mapping.handle(key: 1, down: false, repeating: false, modifiers: [],
            windowsKey: .option, printScreen: .snipping, allowed: false)
        #expect(release?.key == 21 && release?.modifiers == [])
        #expect(!mapping.hasHeldKeys)
    }
    @Test func anotherSourceCannotReplaceOrReleaseTheHeldScreenshotKey() {
        var mapping = NativeScreenshotMapping()
        _ = mapping.handle(key: 1, down: true, repeating: false, modifiers: [.option, .shift],
            windowsKey: .option, printScreen: .snipping, allowed: true, sourcePID: 10)
        #expect(mapping.handle(key: 1, down: true, repeating: false, modifiers: [.option, .shift],
            windowsKey: .option, printScreen: .snipping, allowed: true, sourcePID: 20) == nil)
        #expect(mapping.handle(key: 1, down: false, repeating: false, modifiers: [],
            windowsKey: .option, printScreen: .snipping, allowed: false, sourcePID: 20) == nil)
        #expect(mapping.reset() == [21] && !mapping.hasHeldKeys)
    }
    @Test func noCaptureForSaveAsProtectedPolicyOrAnAlreadyNativeScreenshot() {
        var mapping = NativeScreenshotMapping()
        for modifiers: Modifiers in [[.control, .shift], [.option, .control, .shift], [.command, .shift]] {
            #expect(mapping.handle(key: 1, down: true, repeating: false, modifiers: modifiers,
                windowsKey: .option, printScreen: .snipping, allowed: true) == nil)
        }
        #expect(mapping.handle(key: 1, down: true, repeating: false, modifiers: [.option, .shift],
            windowsKey: .option, printScreen: .snipping, allowed: false) == nil)
        #expect(mapping.handle(key: 21, down: true, repeating: false, modifiers: [.command, .control, .shift],
            windowsKey: .option, printScreen: .snipping, allowed: true) == nil)
    }
}
