import Testing
import BridgeCore

struct MacBookKeyboardMappingTests {
    private let builtIn = MacBookKeyboardIdentity(registryID: 1, builtIn: true, vendorID: 1452,
                                                  transport: "SPI", product: "Apple Internal Keyboard / Trackpad")
    @Test func onlyLocalPhysicalPortableKeyboardIsEligible() {
        #expect(builtIn.isLocalMacBookKeyboard(portable: true))
        #expect(!builtIn.isLocalMacBookKeyboard(portable: false))
        var external = builtIn; external.builtIn = false; external.transport = "USB"
        #expect(!external.isLocalMacBookKeyboard(portable: true))
        var remote = builtIn; remote.product = "V-Apple Internal Keyboard / Trackpad"
        #expect(!remote.isLocalMacBookKeyboard(portable: true))
        remote.product = "Apple Internal Keyboard"; remote.virtual = true
        #expect(!remote.isLocalMacBookKeyboard(portable: true))
        remote.virtual = false; remote.transport = "Bluetooth"
        #expect(!remote.isLocalMacBookKeyboard(portable: true))
        remote.transport = "SPI"; remote.vendorID = 1133
        #expect(!remote.isLocalMacBookKeyboard(portable: true))
    }
    @Test func swapIncludesBothAppleFnUsagesAndOnlyLeftControl() {
        #expect(MacBookFnControlMapping.swap == [NativeKeyMapping(UInt64(0xff) << 32 | 3, 0x7000000e0),
            NativeKeyMapping(UInt64(0xff01) << 32 | 3, 0x7000000e0), NativeKeyMapping(0x7000000e0, UInt64(0xff) << 32 | 3)])
        for key: UInt64 in [0x7000000e4, 0x7000000e2, 0x7000000e3, 0x7000000e6, 0x7000000e7] {
            #expect(!MacBookFnControlMapping.owns(key))
        }
    }
    @Test func mergeAndRestorationRetainUnrelatedMappingsAndIdentities() {
        let original = [NativeKeyMapping(0x700000039, 0x700000029),
                        NativeKeyMapping(MacBookFnControlMapping.leftControl, MacBookFnControlMapping.leftControl)]
        #expect(!MacBookFnControlMapping.hasUserConflict(original))
        let mapped = MacBookFnControlMapping.applying(to: original)
        #expect(MacBookFnControlMapping.containsSwap(mapped))
        #expect(MacBookFnControlMapping.applying(to: mapped) == mapped)
        #expect(MacBookFnControlMapping.restoring(mapped, original: original) == original)
    }
    @Test func concurrentOwnedAndUnrelatedChangesSurviveRestoration() {
        let other = NativeKeyMapping(0x700000004, 0x700000005)
        let external = NativeKeyMapping(MacBookFnControlMapping.leftControl, 0x7000000e3)
        var current = MacBookFnControlMapping.swap.filter { $0.source != external.source }
        current += [external, other]
        #expect(!MacBookFnControlMapping.containsSwap(current))
        #expect(MacBookFnControlMapping.hasUserConflict(current))
        #expect(MacBookFnControlMapping.restoring(current, original: []) == [external, other])
    }
    @Test func systemModifierCompositionCannotSwapControlTwice() {
        let ctrlToCommand = NativeKeyMapping(MacBookFnControlMapping.leftControl, 0x7000000e3)
        let altToCtrl = NativeKeyMapping(0x7000000e2, MacBookFnControlMapping.leftControl)
        #expect(MacBookFnControlMapping.hasModifierConflict([ctrlToCommand]))
        #expect(MacBookFnControlMapping.hasModifierConflict([altToCtrl]))
        #expect(!MacBookFnControlMapping.hasModifierConflict([NativeKeyMapping(0x7000000e2, 0x7000000e3)]))
    }
}
