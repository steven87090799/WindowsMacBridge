import Foundation
import Testing
@testable import BridgeCore

struct DriverApprovalTests {
    @Test func waitingDisabledAndOtherDevelopersNeverBecomeGreen() {
        let approved = "*\t*\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0)\tDriver\t[activated enabled]"
        #expect(DriverApproval.isEnabled(in: approved))
        #expect(!DriverApproval.isEnabled(in: approved.replacingOccurrences(of: "[activated enabled]", with: "[activated waiting for user]")))
        #expect(!DriverApproval.isEnabled(in: "\t" + approved.dropFirst(2)))
        #expect(!DriverApproval.isEnabled(in: approved.replacingOccurrences(of: "G43BCU2T37", with: "OTHERTEAM")))
        #expect(!DriverApproval.isEnabled(in: "Driver package installed"))
        #expect(DriverApproval.isRegistered(in: approved.replacingOccurrences(of: "[activated enabled]", with: "[activated waiting for user]")))
        #expect(!DriverApproval.isRegistered(in: approved.replacingOccurrences(of: "G43BCU2T37", with: "OTHERTEAM")))
    }
}
