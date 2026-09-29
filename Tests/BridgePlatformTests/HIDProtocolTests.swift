import Foundation
import Testing
import BridgeCore
import BridgePlatform
import HIDProtocol

struct HIDProtocolTests {
    @Test func newInstallUsesChatPresetAndLegacySettingsPreserveEventTap() throws {
        let settings = BridgeSettings()
        #expect(settings.enabled); #expect(settings.inputBackend == .eventTap)
        #expect(settings.keyboardScope == .allKeyboards)
        #expect(settings.screenshotAutoCopy)
        #expect(settings.overrides["com.openai.codex"] == .macOS)
        let legacy = Data(#"{"schemaVersion":1,"enabled":true,"overrides":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(BridgeSettings.self, from: legacy)
        #expect(decoded.inputBackend == .eventTap); #expect(decoded.keyboardScope == .allKeyboards)
        #expect(decoded.screenshotAutoCopy)
    }
    @Test func boundedPolicyRejectsUnknownVersionInvalidPIDAndLongBundle() {
        var policy = HIDConfiguration(); #expect(policy.valid)
        policy.enabled = true; #expect(!policy.valid)
        policy.processID = 42; policy.bundleID = "com.apple.Safari"; #expect(policy.valid)
        policy.bundleID = String(repeating: "a", count: 257); #expect(!policy.valid)
        policy.bundleID = "com.apple.Safari"; policy.version = 999; #expect(!policy.valid)
        policy.version = HIDService.protocolVersion; policy.processID = -1; #expect(!policy.valid)
        policy.processID = 42; policy.version = 1; #expect(!policy.valid)
    }
    @Test func remotePolicyAndGenerationRoundTripWithoutKeyboardPayload() throws {
        var policy = HIDConfiguration()
        policy.enabled = true; policy.processID = 42; policy.bundleID = "remote.test"; policy.mode = .remoteWindows
        policy.generation = 7; policy.restartToken = 2
        policy.windowsKeyModifier = .command; policy.macBookFnControlSwap = true
        policy.altF4Enabled = true; policy.textNavigationEnabled = false
        let data = try JSONEncoder().encode(policy); #expect(data.count < 4096)
        let next = try JSONDecoder().decode(HIDConfiguration.self, from: data)
        #expect(next.valid); #expect(next.context.mode == .remoteWindows); #expect(next.generation == 7)
        #expect(next.windowsKeyModifier == .command && next.macBookFnControlSwap)
        #expect(next.altF4Enabled && !next.textNavigationEnabled)
    }
    @Test func onlyFixedActionsAreDecoded() {
        for value in FinderAction.allCases { #expect(HIDActionCodec.decode(HIDActionCodec.encode(.finder(value))) == .finder(value)) }
        for value in SystemAction.allCases { #expect(HIDActionCodec.decode(HIDActionCodec.encode(.system(value))) == .system(value)) }
        #expect(HIDActionCodec.decode("shell.rm") == nil); #expect(HIDActionCodec.decode("keyboard.inject") == nil)
        #expect(HIDActionCodec.decode("finder.unknown") == nil)
    }
}
