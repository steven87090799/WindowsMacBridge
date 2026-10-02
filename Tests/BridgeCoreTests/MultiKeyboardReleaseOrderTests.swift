import Testing
import BridgeCore

struct MultiKeyboardReleaseOrderTests {
    private func permutations(_ values: [Int]) -> [[Int]] {
        if values.isEmpty { return [[]] }
        return values.flatMap { first in permutations(values.filter { $0 != first }).map { [first] + $0 } }
    }
    @Test func everyTwoKeyboardControlShiftAltReleaseOrderPreservesRemainingPhysicalHolds() {
        let holds: [(UInt64, UInt16, UInt8)] = [(1, 0xe0, 1), (1, 0xe1, 2), (1, 0xe2, 4),
                                               (2, 0xe0, 1), (2, 0xe1, 2), (2, 0xe2, 4)]
        for order in permutations(Array(holds.indices)) {
            var engine = HIDTranslationEngine()
            _ = engine.register(1); _ = engine.register(2)
            engine.configure(context: .init(processID: 10, bundleID: "source.Terminal", mode: .terminal),
                layoutSupported: true, finderEnabled: false, transportOnly: true, actionsEnabled: false)
            for (device, usage, _) in holds { _ = engine.observe(device: device, page: 7, usage: usage, down: true) }
            var remaining = Set(holds.indices)
            for index in order {
                let (device, usage, _) = holds[index]
                _ = engine.observe(device: device, page: 7, usage: usage, down: false)
                remaining.remove(index)
                var report = HIDOutput()
                let rendered = engine.render(into: &report)
                #expect(rendered && report.modifiers == remaining.reduce(UInt8(0)) { $0 | holds[$1].2 })
                #expect(report.keyCount == 0)
            }
        }
    }
    @Test func safetyInterruptionAndDisconnectNeverRestoreOldShortcutAcrossReleasePermutations() {
        for order in permutations([0, 1, 2, 3]) {
            for disconnect in [false, true] {
                var engine = HIDTranslationEngine()
                _ = engine.register(1); _ = engine.register(2)
                engine.configure(context: .init(processID: 10, bundleID: "test", mode: .macOS),
                    layoutSupported: true, finderEnabled: false)
                let holds: [(UInt64, UInt16)] = [(1, 0xe0), (2, 0xe1), (2, 0xe2), (1, 6)]
                // Start translated copy before overlapping Shift and Alt.
                for i in [0, 3, 1, 2] { _ = engine.observe(device: holds[i].0, page: 7, usage: holds[i].1, down: true) }
                engine.invalidate()
                if disconnect { engine.disconnect(2) }
                for i in order {
                    _ = engine.observe(device: holds[i].0, page: 7, usage: holds[i].1, down: false)
                    var report = HIDOutput(); let rendered = engine.render(into: &report)
                    #expect(rendered && report.isEmpty)
                }
                _ = engine.observe(device: 1, page: 7, usage: 0xe0, down: true)
                _ = engine.observe(device: 1, page: 7, usage: 6, down: true)
                var report = HIDOutput(); let rendered = engine.render(into: &report)
                #expect(rendered && report.modifiers == 8 && report.keyCount == 1)
            }
        }
    }
}
