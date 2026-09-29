import Foundation
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor private final class ModeProbe {
    var received: [Bool] = []
    var hadDictionary = false
    func waitForCount(_ expected: Int) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while received.count < expected && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(received.count >= expected, "Native distributed notification was not received")
    }
}

/// A private notification namespace: never changes the installed App or Finder.
@MainActor struct FinderModePublisherTests {
    @Test func nativeHandshakeUpdatesAndStopsWithoutSharedContainer() async {
        let center = DistributedNotificationCenter.default()
        let channel = FinderModeChannel(namespace: "local.WindowsMacBridge.tests." + UUID().uuidString)
        let probe = ModeProbe()
        let token = center.addObserver(forName: channel.stateName, object: nil, queue: .main) { notification in
            let value = FinderModeChannel.enabled(from: notification.object)
            let dictionary = notification.userInfo != nil
            MainActor.assumeIsolated {
                if let value { probe.received.append(value) }
                probe.hadDictionary = probe.hadDictionary || dictionary
            }
        }
        defer { center.removeObserver(token) }
        let publisher = FinderModePublisher(center: center, channel: channel)
        publisher.start(enabled: false)
        await probe.waitForCount(1)
        #expect(probe.received.last == false)
        publisher.setEnabled(true)
        await probe.waitForCount(2)
        #expect(probe.received.last == true)
        center.postNotificationName(channel.requestName, object: FinderModeChannel.requestObject,
                                    userInfo: nil, deliverImmediately: true)
        await probe.waitForCount(3)
        #expect(probe.received.last == true)
        publisher.stop()
        await probe.waitForCount(4)
        #expect(probe.received.last == false)
        let count = probe.received.count
        center.postNotificationName(channel.requestName, object: FinderModeChannel.requestObject,
                                    userInfo: nil, deliverImmediately: true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(probe.received.count == count)
        #expect(!probe.hadDictionary)
    }
}
