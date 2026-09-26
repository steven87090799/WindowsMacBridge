// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Darwin
import Foundation

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

    private enum Key {
        static let automaticCorrectionCount = "inputSource.diagnostics.automaticCorrectionCount"
        static let failedSelectionCount = "inputSource.diagnostics.failedSelectionCount"
        static let secureInputWaitCount = "inputSource.diagnostics.secureInputWaitCount"
        static let lastSuccessfulSelectionAt = "inputSource.diagnostics.lastSuccessfulSelectionAt"
        static let vChewingRestoreCount = "inputSource.diagnostics.vChewingRestoreCount"
        static let recentVChewingRestoreTimes = "inputSource.diagnostics.recentVChewingRestoreTimes"
    }

    private let defaults = UserDefaults.standard
    private let maximumRecentRestoreTimes = 20

    private init() {}

    var automaticCorrectionCount: Int {
        defaults.integer(forKey: Key.automaticCorrectionCount)
    }

    var failedSelectionCount: Int {
        defaults.integer(forKey: Key.failedSelectionCount)
    }

    var secureInputWaitCount: Int {
        defaults.integer(forKey: Key.secureInputWaitCount)
    }

    var lastSuccessfulSelectionAt: Date? {
        defaults.object(forKey: Key.lastSuccessfulSelectionAt) as? Date
    }

    var vChewingRestoreCount: Int {
        defaults.integer(forKey: Key.vChewingRestoreCount)
    }

    var recentVChewingRestoreTimes: [Date] {
        defaults.array(forKey: Key.recentVChewingRestoreTimes) as? [Date] ?? []
    }

    func recordSelectionSuccess(automatic: Bool, restoredVChewing: Bool) {
        let now = Date()
        defaults.set(now, forKey: Key.lastSuccessfulSelectionAt)

        if automatic {
            defaults.set(automaticCorrectionCount + 1, forKey: Key.automaticCorrectionCount)
        }

        if restoredVChewing {
            defaults.set(vChewingRestoreCount + 1, forKey: Key.vChewingRestoreCount)
            var recent = recentVChewingRestoreTimes
            recent.append(now)
            if recent.count > maximumRecentRestoreTimes {
                recent.removeFirst(recent.count - maximumRecentRestoreTimes)
            }
            defaults.set(recent, forKey: Key.recentVChewingRestoreTimes)
            FileLogger.shared.log(
                "Guard restored vChewing Traditional at \(Self.timestamp(now)); total restores: \(vChewingRestoreCount)"
            )
        }
    }

    func recordFailedSelection() {
        defaults.set(failedSelectionCount + 1, forKey: Key.failedSelectionCount)
    }

    func recordSecureInputWait() {
        defaults.set(secureInputWaitCount + 1, forKey: Key.secureInputWaitCount)
    }

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
            "自動 correction 成功：\(automaticCorrectionCount) 次",
            "Failed select：\(failedSelectionCount) 次",
            "Secure Input 等待：\(secureInputWaitCount) 次",
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
