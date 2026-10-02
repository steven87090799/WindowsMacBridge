import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor struct KeyboardPermissionRequestTests {
    @Test func accessibilityAloneCannotTurnTheCombinedKeyboardControlCheckGreen() {
        let axOnly = PermissionSnapshot(accessibility: true, posting: false)
        #expect(!axOnly.keyboardControlGranted)
        #expect(KeyboardPermissionRequest.plan(for: axOnly) == [.posting])
        #expect(PermissionSnapshot(accessibility: true, posting: true).keyboardControlGranted)
    }
    @Test func explicitRepairCallsMissingNativeRequestAndNeverTreatsRequestReturnAsGrant() {
        var requests: [PermissionKind] = []
        let initial = PermissionSnapshot(accessibility: true, posting: false)
        let result = KeyboardPermissionRequest.perform(read: { initial }, request: { requests.append($0); return true })
        #expect(requests == [.posting])
        #expect(!result.posting && !result.keyboardControlGranted)
    }
    @Test func refreshDoesNotRequestAnythingAndPreviouslyGrantedCapabilitiesAreNotRequestedAgain() {
        let complete = PermissionSnapshot(accessibility: true, posting: true)
        #expect(KeyboardPermissionRequest.plan(for: complete).isEmpty)
        var calls = 0
        let result = KeyboardPermissionRequest.perform(read: { complete }, request: { _ in calls += 1; return false })
        #expect(calls == 0 && result.keyboardControlGranted)
        #expect(KeyboardPermissionRequest.plan(for: .init(posting: true)) == [.accessibility])
        #expect(KeyboardPermissionRequest.plan(for: .init()) == [.posting])
    }
    @Test func oneClickDoesNotStackTwoNativePermissionPrompts() {
        let initial = PermissionSnapshot()
        var requests: [PermissionKind] = []
        let result = KeyboardPermissionRequest.perform(read: { initial }, request: {
            requests.append($0)
            return false
        })
        #expect(requests == [.posting])
        #expect(!result.keyboardControlGranted)
    }
}
