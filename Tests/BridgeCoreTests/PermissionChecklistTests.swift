import Testing
@testable import BridgeCore

struct PermissionChecklistTests {
    @Test func grantsAreNeverInferredFromUncheckedOrPendingState() {
        var state = PermissionChecklistState()
        #expect(state.verification(for: [.listening]) == .unchecked)
        state.verify(.init(accessibility: true, posting: true, listening: false))
        #expect(state.verification(for: [.accessibility, .posting]) == .granted)
        #expect(state.verification(for: [.listening]) == .denied)
        state.beginNavigation(to: .posting)
        #expect(state.verification(for: [.accessibility, .posting]) == .awaitingVerification)
        state.verify(.init(accessibility: true, posting: false))
        #expect(state.verification(for: [.accessibility, .posting]) == .denied)
        #expect(PermissionVerification(verifiedGrant: nil) == .unchecked)
        #expect(PermissionVerification(verifiedGrant: false) == .denied)
    }
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
