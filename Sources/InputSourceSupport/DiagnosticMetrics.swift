// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Foundation
import InputSourceCore

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

    func summary() -> String {
        let lastSuccess = lastSuccessfulSelectionAt.map(Self.timestamp) ?? "尚無"
        let recent = recentVChewingRestoreTimes
            .suffix(8)
            .reversed()
            .map(Self.timestamp)
            .joined(separator: "、")

        return [
            "自動修正成功：\(automaticCorrectionCount) 次",
            "切換失敗：\(failedSelectionCount) 次",
            "Secure Input 等待：\(secureInputWaitCount) 次",
            "舊版保留外部切換：\(statistics.preservedExternalSelections) 次",
            "最後成功切換：\(lastSuccess)",
            "程式切回唯音：\(vChewingRestoreCount) 次",
            "最近程式切回唯音時間：\(recent.isEmpty ? "尚無" : recent)",
        ].joined(separator: "\n")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
