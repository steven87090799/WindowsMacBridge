import Testing
@testable import BridgeCore

struct PhysicalDevicePolicyTests {
    @Test func appleAndBuiltInDevicesReceiveWindowsExperienceUnlessIndividuallyOverridden() {
        for builtIn in [false,true] {
            #expect(PhysicalDevicePolicy.selected(identity: "a", scope: .allKeyboards, builtIn: builtIn, apple834: true, preferences: []))
            let prefs: [DeviceInputPreference] = [.init(identity: "a", experience: .nativeMac)]
            #expect(!PhysicalDevicePolicy.selected(identity: "a", scope: .allKeyboards, builtIn: builtIn, apple834: true, preferences: prefs))
            #expect(PhysicalDevicePolicy.selected(identity: "b", scope: .allKeyboards, builtIn: builtIn, apple834: true, preferences: prefs))
        }
    }
    @Test func virtualUCAndOwnOutputsCannotBeSeized() {
        for product in ["Universal Control", "VirtualHIDDevice", "V-Keyboard", "Virtual Keyboard"] {
            #expect(PhysicalDevicePolicy.isVirtual(product: product, vendor: 1452, virtualProperty: false, transport: ""))
        }
        #expect(PhysicalDevicePolicy.isVirtual(product: "Keyboard", vendor: 0x16c0, virtualProperty: false, transport: "USB"))
        #expect(!PhysicalDevicePolicy.isVirtual(product: "Apple Internal Keyboard", vendor: 1452, virtualProperty: false, transport: "SPI"))
    }
    @Test func fallbackNeverSilentlyOverridesNativeDevicePreference() {
        let preferences: [DeviceInputPreference] = [.init(identity: "native", experience: .nativeMac)]
        #expect(!BackendCapabilities.eventTap.supports(.allKeyboards, preferences: preferences))
        #expect(BackendCapabilities.eventTap.supports(.allKeyboards, preferences: [.init(identity: "a", experience: .windows)]))
    }
    @Test func deviceIdentitySurvivesRegistryIDChangeAndDoesNotContainSerial() {
        let a = PhysicalDevicePolicy.identity(vendor: 1452, product: 834, location: 1, transport: "USB", builtIn: false, serial: "private-serial")
        #expect(a.count == 64 && !a.contains("private-serial"))
        #expect(a == PhysicalDevicePolicy.identity(vendor: 1452, product: 834, location: 1, transport: "USB", builtIn: false, serial: "private-serial"))
        #expect(a == PhysicalDevicePolicy.identity(vendor: 1452, product: 834, location: 2, transport: "USB", builtIn: false, serial: "private-serial"))
        #expect(PhysicalDevicePolicy.identity(vendor: 1, product: 1, location: 1, transport: "USB", builtIn: false) !=
                PhysicalDevicePolicy.identity(vendor: 1, product: 1, location: 2, transport: "USB", builtIn: false))
    }
    @Test func relinquishingOneDeviceDoesNotReleaseIndependentChordOnTheOther() {
        var e = HIDTranslationEngine(); _ = e.register(1); _ = e.register(2)
        e.configure(context: .init(processID: 1, bundleID: "editor", mode: .macOS), layoutSupported: true, finderEnabled: false)
        _ = e.observe(device: 1, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 2, page: 7, usage: 0xe0, down: true)
        _ = e.observe(device: 2, page: 7, usage: 6, down: true)
        e.disconnect(1)
        var out = HIDOutput(); _ = e.render(into: &out)
        #expect(out.modifiers == 8 && out.keyCount == 1 && out.keys[0] == 6)
        _ = e.observe(device: 2, page: 7, usage: 6, down: false)
        _ = e.observe(device: 2, page: 7, usage: 9, down: true)
        _ = e.render(into: &out); #expect(out.modifiers == 8 && out.keyCount == 1)
    }
}
