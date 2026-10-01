import Testing
@testable import BridgeCore

struct SourceWorkGateTests {
    @Test func simultaneousValidationCannotInventRevocationAndDropPairedKeyUp() async {
        let gate = SourceWorkGate()
        let failures = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var failed = 0
                    for _ in 0..<20_000 {
                        _ = gate.isCurrent
                        if !gate.isCurrentWithoutWaiting { failed += 1 }
                    }
                    return failed
                }
            }
            var total = 0
            for await value in group { total += value }
            return total
        }
        #expect(failures == 0)
        gate.invalidate()
        #expect(!gate.isCurrent && !gate.isCurrentWithoutWaiting)
    }
}
