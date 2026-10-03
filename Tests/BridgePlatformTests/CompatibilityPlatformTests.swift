import Foundation
import Testing
import BridgeCore
@testable import BridgePlatform

struct CompatibilityPlatformTests {
    @Test func remoteFamiliesAndExecutableFallback() throws {
        let registry = try ApplicationRegistry()
        for id in ["com.edovia.Screens5", "com.moonlight-stream.Moonlight", "com.royalapps.RoyalTSX.v6",
                   "com.philandro.anydesk", "com.parsec.app", "com.citrix.workspace", "com.p5sys.jump.preview",
                   "com.nomachine.nxplayer", "com.realvnc.viewer", "com.teamviewer.preview", "tv.parsec.www",
                   "com.aweray.awesun.macclient", "com.aweray.awesun.preview"] {
            #expect(registry.mode(for: id, overrides: [:]) == .remoteWindows)
        }
        #expect(registry.mode(for: "com.vmware.vmrc", overrides: [:]) == .virtualMachine)
        #expect(registry.mode(for: "unknown.helper", executablePath: "/Applications/Windows App.app/Contents/MacOS/client", overrides: [:]) == .remoteWindows)
        #expect(registry.mode(for: "unknown.helper", executablePath: "/Users/person/Applications/Jump Desktop.app/Contents/MacOS/client", overrides: [:]) == .remoteWindows)
        #expect(registry.mode(for: "unknown.helper", executablePath: "/Applications/AweSun.app/Contents/MacOS/AweSun", overrides: [:]) == .remoteWindows)
        #expect(registry.mode(for: "unknown.helper", executablePath: "/Applications/NotRemote.app/Contents/MacOS/client", overrides: [:]) == .macOS)
        #expect(registry.mode(for: "com.microsoft.VSCodeInsiders", overrides: [:]) == .ide)
        #expect(registry.mode(for: "dev.warp.Warp-Preview", overrides: [:]) == .terminal)
    }
    @Test func browserDetectionIsSpecific() throws {
        let registry = try ApplicationRegistry()
        for id in ["com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "company.thebrowser.Browser",
                   "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(registry.isBrowser(id))
        }
        #expect(!registry.isBrowser("test.com.apple.Safari"))
        #expect(!registry.isBrowser("com.microsoft.VSCode"))
    }
    @Test func imePhysicalShortcutsRequireExplicitOptionAndASCIILayout() {
        #expect(!KeyboardLayoutResolver.supports(sourceID: "org.vchewing.inputmethod.vChewing", asciiLayoutID: "com.apple.keylayout.ABC", allowIME: false))
        #expect(KeyboardLayoutResolver.supports(sourceID: "org.vchewing.inputmethod.vChewing", asciiLayoutID: "com.apple.keylayout.ABC", allowIME: true))
        #expect(!KeyboardLayoutResolver.supports(sourceID: "unknown", asciiLayoutID: "com.apple.keylayout.ABC", allowIME: true))
        #expect(!KeyboardLayoutResolver.supports(sourceID: "com.apple.inputmethod.TCIM", asciiLayoutID: "com.apple.keylayout.Dvorak", allowIME: true))
    }
    @Test func legacySettingsDecodeAndNewScopeRoundTrips() throws {
        let old = Data(#"{"schemaVersion":1,"enabled":true,"overrides":{"com.apple.Terminal":"terminal"}}"#.utf8)
        let settings = try JSONDecoder().decode(BridgeSettings.self, from: old)
        #expect(settings.enabled)
        #expect(settings.keyboardScope == .allKeyboards)
        #expect(settings.finderEnabled)
        #expect(!settings.allowIMEShortcuts)
        let fresh = BridgeSettings()
        #expect(fresh.keyboardScope == .allKeyboards)
        #expect(fresh.enabled)
        let restored = try JSONDecoder().decode(BridgeSettings.self, from: JSONEncoder().encode(fresh))
        #expect(restored.keyboardScope == fresh.keyboardScope)
    }
}
