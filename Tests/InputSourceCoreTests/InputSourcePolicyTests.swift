import Testing
import BridgeCore

struct InputSourcePolicyTests {
    private func context(_ mode: ApplicationMode) -> ApplicationContext {
        .init(processID: 123, bundleID: "test.application", mode: mode)
    }
    @Test(arguments: [ApplicationMode.remoteWindows, .virtualMachine, .game, .disabled])
    func protectedProfilesSuspendBothInputFeatures(_ mode: ApplicationMode) {
        #expect(InputSourcePolicy.suspension(context: context(mode), isHostApp: false,
            paused: false, sessionActive: true) == .protectedApplication)
        #expect(!mode.allowsTranslation)
    }
    @Test(arguments: [ApplicationMode.macOS, .terminal, .ide])
    func localSourceSelectionDoesNotChangeShortcutPolicy(_ mode: ApplicationMode) {
        #expect(InputSourcePolicy.suspension(context: context(mode), isHostApp: false,
            paused: false, sessionActive: true) == nil)
        #expect(mode.allowsTranslation == (mode == .macOS))
    }
    @Test func settingsCanSelectButPauseAndSessionSuspensionOverride() {
        let app = context(.disabled)
        #expect(InputSourcePolicy.suspension(context: app, isHostApp: true,
            paused: false, sessionActive: true) == nil)
        #expect(InputSourcePolicy.suspension(context: app, isHostApp: true,
            paused: true, sessionActive: true) == .paused)
        #expect(InputSourcePolicy.suspension(context: app, isHostApp: true,
            paused: false, sessionActive: false) == .inactiveSession)
    }
    @Test func missingForegroundFailsClosed() {
        #expect(InputSourcePolicy.suspension(context: .init(), isHostApp: false,
            paused: false, sessionActive: true) == .unknownApplication)
    }
    @Test func leavingRemoteRestoresLocalPolicyWithoutOverridingPause() {
        let contexts = [context(.macOS), context(.remoteWindows), context(.virtualMachine), context(.macOS)]
        let expected: [InputSourceSuspension?] = [nil, .protectedApplication, .protectedApplication, nil]
        for (app, reason) in zip(contexts, expected) {
            #expect(InputSourcePolicy.suspension(context: app, isHostApp: false,
                paused: false, sessionActive: true) == reason)
            #expect(InputSourcePolicy.suspension(context: app, isHostApp: false,
                paused: true, sessionActive: true) == .paused)
        }
    }
}
