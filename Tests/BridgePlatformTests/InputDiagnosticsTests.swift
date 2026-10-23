import Darwin
import Foundation
import Testing
@testable import BridgePlatform

struct InputDiagnosticsTests {
    @Test func disabledAndEmptySessionsAllocateNoRecordStorage() {
        var log = InputDiagnostics()
        log.append(rule: "ignored", application: "app", microseconds: 1, now: 0)
        #expect(log.allocatedSlots == 0 && log.snapshot().isEmpty)
        log.configure(enabled: true, now: 10)
        #expect(log.deadline == 310 && log.allocatedSlots == 0)
        log.append(rule: "copy", application: "app", microseconds: 1, now: 11)
        #expect(log.count == 1 && log.allocatedSlots == 128)
        log.configure(enabled: false, now: 12)
        #expect(log.allocatedSlots == 0 && log.snapshot().isEmpty && log.deadline == nil)
    }

    @Test func expiryReleasesStorageAndOtherConfigurationChangesCannotRestartIt() {
        var log = InputDiagnostics()
        log.configure(enabled: true, now: 10)
        log.append(rule: "copy", application: "app", microseconds: 1, now: 11)
        let revision = log.revision
        #expect(!log.isActive(at: 310))
        log.expire(at: 310)
        #expect(log.revision != revision && log.allocatedSlots == 0 && log.snapshot().isEmpty)
        log.configure(enabled: true, now: 311)
        log.append(rule: "ignored", application: "app", microseconds: 1, now: 312)
        #expect(log.deadline == nil && log.allocatedSlots == 0)
        log.configure(enabled: false, now: 313)
        log.configure(enabled: true, now: 314)
        #expect(log.deadline == 614 && log.isActive(at: 315))
    }

    @Test func ringReturnsOnlyNewestRecordsInOrderAndBoundsUTF8Payloads() {
        var log = InputDiagnostics()
        log.configure(enabled: true, now: 0)
        let large = String(repeating: "測試🙂", count: 1_000)
        for i in 1...300 {
            log.append(rule: large, application: large, microseconds: Double(i), detail: large, now: 1)
        }
        let records = log.snapshot()
        #expect(log.allocatedSlots == 128 && records.count == 128)
        #expect(records.map(\.id) == Array((173...300).reversed()).map(UInt64.init))
        #expect(records.allSatisfy { $0.rule.utf8.count <= 256 && $0.application.utf8.count <= 256 &&
            ($0.detail?.utf8.count ?? 0) <= 1024 && $0.detail?.contains("�") == false })
        let revision = log.revision
        log.configure(enabled: true, now: 100)
        #expect(log.revision == revision && log.deadline == 300)
    }

    @Test func repeatedTraceSnapshotsKeepMemoryBounded() {
        // Run in the isolated memory-test process: footprint includes the entire process.
        var log = InputDiagnostics()
        log.configure(enabled: true, now: 0)
        var latest: [DiagnosticRecord] = []
        func cycle(_ value: Int) {
            log.append(rule: "input-shortcut", application: "synthetic.editor", microseconds: 1,
                detail: "key=8 flags=1 source=0/1 target=10 synchronized=true result=rewrite:windows.copy sample=\(value)", now: 1)
            latest = log.snapshot()
        }
        for i in 0..<2_000 { cycle(i) }
        let before = diagnosticFootprint()
        for i in 0..<50_000 { cycle(i) }
        let after = diagnosticFootprint()
        print("Diagnostic trace memory: before=\(before) after=\(after) bytes; 50000 snapshots; retained=\(latest.count)")
        #expect(before > 0 && after > 0)
        #expect(after < before + 8 * 1024 * 1024, "trace count must not accumulate record or snapshot storage")
        #expect(log.allocatedSlots == 128 && latest.count == 128)
        log.expire(at: 300); latest = log.snapshot()
        #expect(log.allocatedSlots == 0 && latest.isEmpty)
    }
}

private func diagnosticFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}
