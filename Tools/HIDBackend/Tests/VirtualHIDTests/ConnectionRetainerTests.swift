import Testing
import HIDLifecycle

struct ConnectionRetainerTests {
    private final class Peer {}
    @Test func readOnlyPeerLivesUntilInvalidationWithoutCaptureOwner() {
        let connections = ConnectionRetainer<Peer>()
        var accepted: Peer? = Peer()
        weak var observed = accepted
        #expect(connections.insert(accepted!))
        accepted = nil
        #expect(observed != nil)
        #expect(!connections.isEmpty)
        if let observed { connections.remove(observed) }
        #expect(observed == nil)
        #expect(connections.isEmpty)
    }
    @Test func boundedPeersAndIndependentInvalidation() {
        let connections = ConnectionRetainer<Peer>(limit: 2)
        let controller = Peer(), probe = Peer(), excess = Peer()
        #expect(connections.insert(controller))
        #expect(connections.insert(probe))
        #expect(!connections.insert(excess))
        connections.remove(controller)
        #expect(!connections.isEmpty)
        #expect(connections.insert(excess))
        connections.remove(probe)
        #expect(!connections.isEmpty)
        connections.remove(excess)
        #expect(connections.isEmpty)
    }
}
