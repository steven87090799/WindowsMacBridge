import Foundation
import Testing
@testable import BridgeCore

struct FinderModeSignalTests {
    @Test func protocolAcceptsOnlyVersionedBooleanStrings() {
        #expect(FinderModeChannel.enabled(from: FinderModeChannel.object(enabled: true)) == true)
        #expect(FinderModeChannel.enabled(from: FinderModeChannel.object(enabled: false)) == false)
        for value: Any? in [nil, true, 1, "enabled", "v2:enabled", "v1", "v1:enabled:path", String(repeating: "x", count: 4096)] {
            #expect(FinderModeChannel.enabled(from: value) == nil)
        }
    }
    @Test func testNamespaceDoesNotReachInstalledExtension() {
        let test = FinderModeChannel(namespace: "test." + UUID().uuidString)
        #expect(test.requestName != FinderModeChannel.current.requestName)
        #expect(test.stateName != FinderModeChannel.current.stateName)
        #expect(FinderModeChannel.requestObject == "v1")
    }
}
