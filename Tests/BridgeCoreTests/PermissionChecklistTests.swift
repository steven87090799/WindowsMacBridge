import Testing
@testable import BridgeCore

struct PermissionChecklistTests {
    @Test func openingEverySettingsPageNeverGrantsMissingAccess() {
        for kind in PermissionKind.allCases {
            var state = PermissionChecklistState()
            state.beginNavigation(to: kind)
            #expect(!state.verified[kind])
            #expect(state.awaitingVerification.contains(kind))
        }
    }
    @Test func navigationInvalidatesOnlyThePermissionBeingChecked() {
        var state = PermissionChecklistState()
        state.verify(PermissionSnapshot(accessibility: true, screenRecording: true, loginItem: true))
        state.beginNavigation(to: .screenRecording)
        #expect(!state.verified.screenRecording)
        #expect(state.verified.accessibility)
        #expect(state.verified.loginItem)
    }
    @Test func returningWithoutApprovalOrCancellingRemainsDenied() {
        var state = PermissionChecklistState()
        state.beginNavigation(to: .screenRecording)
        state.verify(PermissionSnapshot())
        #expect(!state.verified.screenRecording)
        #expect(state.awaitingVerification.isEmpty)
    }
    @Test func onlyActualNativeApprovalChangesToGranted() {
        var state = PermissionChecklistState()
        state.beginNavigation(to: .accessibility)
        #expect(!state.verified.accessibility)
        state.verify(PermissionSnapshot(accessibility: true, posting: true))
        #expect(state.verified.accessibility)
        #expect(state.verified.posting)
        #expect(!state.verified.screenRecording)
    }
    @Test func revocationAndRestartDoNotReusePreviousGrant() {
        var state = PermissionChecklistState()
        state.verify(PermissionSnapshot(screenRecording: true))
        state.verify(PermissionSnapshot())
        #expect(!state.verified.screenRecording)
        #expect(!PermissionChecklistState().verified.screenRecording)
    }
}
