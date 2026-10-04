import Carbon
import Foundation
import Testing
import BridgeCore
import InputSourceCore
@testable import InputSourceSupport

private final class TestInputSources: InputSourceProviding {
    let traditionalIdentifier: String? = "test.vChewing"
    let abcIdentifier: String? = "test.ABC"
    var current = "test.vChewing"
    var secure = false
    var applySelection = true
    var selections: [String] = []
    var discovery: InputSourceDiscovery {
        .init(traditional: .init(identifier: traditionalIdentifier!),
              abc: .init(identifier: abcIdentifier!), vChewingCandidates: [])
    }
    func rediscover(logChanges: Bool) -> InputSourceDiscovery { discovery }
    func currentSource() -> CurrentInputSourceInfo { .init(identifier: current, localizedName: current) }
    func select(_ source: InputSourceInfo) -> OSStatus {
        selections.append(source.identifier)
        if applySelection { current = source.identifier }
        return noErr
    }
}

@MainActor private final class GuardFixture {
    let name = "GuardControllerIntentTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let sources = TestInputSources()
    let controller: GuardController
    init(enabled: Bool = true, secureRecoveryDelays: [Double]? = nil) {
        defaults = UserDefaults(suiteName: name)!
        defaults.set("com.apple.keylayout.ABC", forKey: "inputSource.preservedSourceIdentifier")
        let sources = self.sources
        controller = GuardController(inputSources: sources,
            selectionStore: GuardSelectionStore(defaults: defaults), isEnabled: enabled,
            secureInputEnabled: { sources.secure },
            secureRecoveryDelays: secureRecoveryDelays ?? GuardController.Configuration.secureInputPollDelaysSeconds.map(Double.init))
        // No native selection is permitted; every read/select uses test metadata.
        controller.selectionAllowed = { false }
    }
    func start() {
        controller.start()
        controller.selectionAllowed = { true }
    }
    func close() {
        controller.stop()
        defaults.removePersistentDomain(forName: name)
    }
    func waitForSelections(_ count: Int, maximumMilliseconds: Int = 3_000) async throws {
        for _ in 0..<(maximumMilliseconds / 25) {
            if sources.selections.count >= count { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(sources.selections.count >= count)
    }
}

@MainActor @Suite(.serialized) struct GuardControllerIntentTests {
    @Test func secureInputWaitIsOneBoundedPassNotAStandingPoll() async throws {
        let fixture = GuardFixture(enabled: false, secureRecoveryDelays: [0.02, 0.02, 0.02]); defer { fixture.close() }
        fixture.sources.current = "test.vChewing"
        fixture.start()
        fixture.sources.secure = true
        fixture.controller.request(.abc)              // explicit request while Secure Input is on
        #expect(fixture.sources.selections.isEmpty)
        #expect(fixture.controller.isWaitingForSecureInputToEnd)
        // Three 20 ms steps, each with the timer's 500 ms leeway; wait for the
        // schedule to run out rather than guessing how long a loaded runner takes.
        for _ in 0..<400 where fixture.controller.isWaitingForSecureInputToEnd { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!fixture.controller.isWaitingForSecureInputToEnd, "the wait must end after one pass")
        fixture.sources.secure = false
        try await Task.sleep(for: .milliseconds(300))
        // A standing poll would have selected ABC as soon as Secure Input ended.
        #expect(fixture.sources.selections.isEmpty)
        // An explicit new request still works.
        fixture.controller.request(.abc)
        try await fixture.waitForSelections(1)
        #expect(fixture.sources.selections == ["test.ABC"])
    }
    @Test func startupAndRefreshIgnoreLegacyPreservedABC() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.sources.current = "test.ABC"
        fixture.start()
        fixture.controller.refreshAndReconcile(reason: "Test refresh")
        #expect(fixture.controller.desired == .vChewing)
        #expect(fixture.controller.statusText == "◌ 等待切換唯音繁體")
        try await fixture.waitForSelections(1)
        #expect(fixture.sources.selections == ["test.vChewing"])
    }

    @Test func externalEnglishNotificationRestoresTraditional() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.sources.current = "test.ABC"
        fixture.controller.handleSelectedSourceChange()
        #expect(fixture.controller.desired == .vChewing)
        #expect(!fixture.controller.statusText.hasPrefix("●"))
        try await fixture.waitForSelections(1)
        #expect(fixture.sources.current == "test.vChewing")
        #expect(GuardSelectionStore(defaults: fixture.defaults).desired == .vChewing)
    }

    @Test func explicitEnglishRemainsTargetAcrossExternalSwitchAndRelaunch() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.controller.request(.abc)
        fixture.controller.handleSelectedSourceChange()
        fixture.sources.current = "test.vChewing"
        fixture.controller.handleSelectedSourceChange()
        try await fixture.waitForSelections(2)
        #expect(fixture.sources.selections == ["test.ABC", "test.ABC"])
        let relaunched = GuardController(inputSources: fixture.sources,
            selectionStore: GuardSelectionStore(defaults: fixture.defaults), isEnabled: true)
        #expect(relaunched.desired == .abc)
    }

    @Test func protectedAppAndDetectionPauseDoNotAdoptEnglish() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.controller.setHostSuspended(true)
        fixture.sources.current = "test.ABC"
        fixture.controller.handleSelectedSourceChange()
        #expect(fixture.sources.selections.isEmpty)
        fixture.controller.setHostSuspended(false)
        try await fixture.waitForSelections(1)
        fixture.controller.handleSelectedSourceChange()
        fixture.controller.pauseDetection(.fifteenMinutes)
        fixture.sources.current = "test.ABC"
        fixture.controller.handleSelectedSourceChange()
        #expect(fixture.sources.selections.count == 1)
        fixture.controller.resumeDetection()
        try await fixture.waitForSelections(2)
        #expect(fixture.sources.selections == ["test.vChewing", "test.vChewing"])
    }

    @Test func secureInputNotificationCannotEraseExplicitRequest() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.sources.secure = true
        fixture.sources.current = "test.ABC"
        fixture.controller.request(.vChewing)
        fixture.sources.current = "test.other"
        fixture.controller.handleSelectedSourceChange()
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.sources.selections.isEmpty)
        #expect(fixture.controller.desired == .vChewing)
        fixture.sources.secure = false
        try await fixture.waitForSelections(1)
        #expect(fixture.sources.selections == ["test.vChewing"])
    }

    @Test func verificationRetriesInsteadOfAdoptingCompetingSource() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.sources.current = "test.ABC"
        fixture.sources.applySelection = false
        fixture.controller.request(.vChewing)
        fixture.sources.current = "test.other"
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.controller.desired == .vChewing)
        fixture.sources.applySelection = true
        try await fixture.waitForSelections(2)
        #expect(fixture.sources.selections == ["test.vChewing", "test.vChewing"])
    }

    @Test func localAppSwitchReschedulesCancelledCorrection() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        let coordinator = InputSourceCoordinator(controller: fixture.controller)
        defer { coordinator.stop() }
        coordinator.liveSelectionAllowed = { true }
        var policy = RuntimePolicyCoordinator()
        var input = RuntimePolicyInput()
        input.foreground = .init(processID: 1, bundleID: "test.first", mode: .macOS)
        coordinator.updateRuntimePolicy(policy.transition(input), protection: nil)
        coordinator.start()
        fixture.sources.current = "test.ABC"
        fixture.controller.handleSelectedSourceChange()
        input.foreground = .init(processID: 2, bundleID: "test.second", mode: .macOS)
        coordinator.updateRuntimePolicy(policy.transition(input), protection: nil)
        try await fixture.waitForSelections(1)
        #expect(fixture.sources.selections == ["test.vChewing"])
    }

    @Test func disabledGuardDoesNotCorrectExternalSelection() {
        let fixture = GuardFixture(enabled: false); defer { fixture.close() }
        fixture.start()
        fixture.sources.current = "test.ABC"
        fixture.controller.handleSelectedSourceChange()
        fixture.controller.refreshAndReconcile(reason: "Test disabled guard")
        #expect(fixture.sources.selections.isEmpty)
        #expect(fixture.controller.desired == .vChewing)
    }

    @Test func hotkeyStillTogglesActualSourceWhenGuardIsDisabled() {
        let fixture = GuardFixture(enabled: false); defer { fixture.close() }
        fixture.start()
        fixture.sources.current = "test.ABC"
        fixture.controller.handleSelectedSourceChange()
        fixture.controller.toggleDesiredSource()
        #expect(fixture.sources.selections == ["test.vChewing"])
        #expect(fixture.controller.desired == .vChewing)
    }

    @Test func expiredPauseRestoresTargetWithoutAdoptingEnglish() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.sources.current = "test.ABC"
        fixture.controller.pauseDetection(.fiveMinutes, now: Date().addingTimeInterval(-301))
        #expect(!fixture.controller.isDetectionPaused)
        try await fixture.waitForSelections(1)
        #expect(fixture.sources.selections == ["test.vChewing"])
    }

    @Test func competingNotificationsCannotResetInFlightRetryBudget() async throws {
        let fixture = GuardFixture(); defer { fixture.close() }
        fixture.start()
        fixture.sources.current = "test.ABC"
        fixture.sources.applySelection = false
        fixture.controller.request(.vChewing)
        fixture.sources.current = "test.other"
        for count in 1...3 {
            try await fixture.waitForSelections(count)
            fixture.controller.handleSelectedSourceChange()
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.sources.selections.count == 3)
        #expect(fixture.controller.desired == .vChewing)
        #expect(fixture.controller.statusText.hasPrefix("⚠"))
    }
}
