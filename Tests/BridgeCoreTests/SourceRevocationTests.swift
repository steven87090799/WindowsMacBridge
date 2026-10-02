import Testing
import BridgeCore

struct SourceRevocationTests {
    @Test func revokedProducerCannotEnterDestinationProcessingFromAnOldSnapshot() {
        for kind: ProducerKind in [.universalControl, .remote, .virtual, .bridge] {
            let producer = RemoteProducer(processID: 42, identity: "fixture", session: 1, revision: 1,
                transport: .generic, confidence: .known, kind: kind)
            let snapshot = InputRoutingSnapshot(producers: [producer])
            let event = InputOriginEvidence(processID: 42, stateID: 1)
            #expect(snapshot.classify(event, physicalBackend: .deviceHID) != .unknown)
            producer.work.invalidate()
            #expect(snapshot.classify(event, physicalBackend: .deviceHID) == .unknown)
        }
    }
}
