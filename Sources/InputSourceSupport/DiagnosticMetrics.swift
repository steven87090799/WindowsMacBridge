// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Darwin
import Foundation
import InputSourceCore

struct ProcessMemorySnapshot {
    let residentBytes: UInt64
    let physicalFootprintBytes: UInt64?

    var description: String {
        let resident = Self.format(bytes: residentBytes)
        guard let physicalFootprintBytes else {
            return "Resident: \(resident)"
        }
        return "Resident: \(resident)；Physical footprint: \(Self.format(bytes: physicalFootprintBytes))"
    }

    private static func format(bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

final class DiagnosticMetrics {
    static let shared = DiagnosticMetrics()

    private let store = InputSourceStatisticsStore(defaults: .standard)

    private init() {
        // This migration reads statistical fields only, never old guard settings
        // or running processes. The prior helper need not be installed.
        if !store.previousStatisticsMigrationCompleted {
            let previous = UserDefaults.standard.persistentDomain(forName: "com.local.VChewingGuard")
            if store.importPreviousStatistics(previous) {
                FileLogger.shared.log("Previous input-source statistics imported once")
            }
        }
    }

    var statistics: InputSourceStatistics { store.snapshot }
    var automaticCorrectionCount: Int { statistics.automaticCorrections }
    var failedSelectionCount: Int { statistics.failedSelections }
    var secureInputWaitCount: Int { statistics.secureInputWaits }
    var lastSuccessfulSelectionAt: Date? { statistics.lastSuccessfulSelection }
    var vChewingRestoreCount: Int { statistics.vChewingRestores }
    var recentVChewingRestoreTimes: [Date] { statistics.recentVChewingRestores }

    func recordSelectionSuccess(automatic: Bool, restoredVChewing: Bool) {
        let now = Date()
        store.recordSelectionSuccess(automatic: automatic, restoredVChewing: restoredVChewing, at: now)
        if restoredVChewing {
            FileLogger.shared.log("Guard restored vChewing Traditional at \(Self.timestamp(now)); total restores: \(vChewingRestoreCount)")
        }
    }

    func recordFailedSelection() { store.recordFailedSelection() }
    func recordSecureInputWait() { store.recordSecureInputWait() }
    func recordPreservedExternalSelection() { store.recordPreservedExternalSelection() }

    func summary(memory: ProcessMemorySnapshot? = nil) -> String {
        let currentMemory = memory ?? DiagnosticMetrics.currentMemorySnapshot()
        let lastSuccess = lastSuccessfulSelectionAt.map(Self.timestamp) ?? "尚無"
        let recent = recentVChewingRestoreTimes
            .suffix(8)
            .reversed()
            .map(Self.timestamp)
            .joined(separator: "、")
        let memoryText = currentMemory?.description ?? "無法讀取"

        return [
            "自動修正成功：\(automaticCorrectionCount) 次",
            "切換失敗：\(failedSelectionCount) 次",
            "Secure Input 等待：\(secureInputWaitCount) 次",
            "保留外部切換：\(statistics.preservedExternalSelections) 次",
            "最後成功切換：\(lastSuccess)",
            "程式切回唯音：\(vChewingRestoreCount) 次",
            "最近程式切回唯音時間：\(recent.isEmpty ? "尚無" : recent)",
            "記憶體：\(memoryText)",
        ].joined(separator: "\n")
    }

    static func currentMemorySnapshot() -> ProcessMemorySnapshot? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return ProcessMemorySnapshot(
            residentBytes: UInt64(info.resident_size),
            physicalFootprintBytes: UInt64(info.phys_footprint)
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
