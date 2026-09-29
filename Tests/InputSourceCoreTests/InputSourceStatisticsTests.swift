import Foundation
import Testing
@testable import InputSourceCore

private final class StatisticsFixture {
    let name = "WindowsMacBridge.StatisticsTests." + UUID().uuidString
    let defaults: UserDefaults
    let store: InputSourceStatisticsStore
    init() {
        defaults = UserDefaults(suiteName: name)!
        store = InputSourceStatisticsStore(defaults: defaults)
    }
    deinit { defaults.removePersistentDomain(forName: name) }
}

struct InputSourceStatisticsTests {
    @Test func previousCountersAreAddedOnceAndDoNotImportSettings() {
        let fixture = StatisticsFixture()
        #expect(!fixture.store.previousStatisticsMigrationCompleted)
        fixture.store.recordFailedSelection()
        let previous: [String: Any] = [
            "diagnostics.automaticCorrectionCount": 12,
            "diagnostics.failedSelectionCount": 3,
            "diagnostics.secureInputWaitCount": 4,
            "diagnostics.vChewingRestoreCount": 8,
            "guardEnabled": true,
            "hotkeyPreset": "optionCommandSpace"
        ]
        #expect(fixture.store.importPreviousStatistics(previous))
        #expect(fixture.store.snapshot.automaticCorrections == 12)
        #expect(fixture.store.snapshot.failedSelections == 4)
        #expect(fixture.store.snapshot.secureInputWaits == 4)
        #expect(fixture.store.snapshot.vChewingRestores == 8)
        #expect(fixture.defaults.object(forKey: "guardEnabled") == nil)
        #expect(fixture.defaults.object(forKey: "hotkeyPreset") == nil)
        let reopened = InputSourceStatisticsStore(defaults: fixture.defaults)
        #expect(reopened.previousStatisticsMigrationCompleted)
        #expect(!reopened.importPreviousStatistics(previous))
        #expect(reopened.snapshot.failedSelections == 4)
        #expect(reopened.snapshot.previousStatisticsImported)
    }
    @Test func recoveryHistoryIsMergedSortedAndBounded() {
        let fixture = StatisticsFixture()
        let newest = Date(timeIntervalSince1970: 100)
        fixture.store.recordSelectionSuccess(automatic: false, restoredVChewing: true, at: newest)
        let oldDates = (0..<35).map { Date(timeIntervalSince1970: Double($0)) }
        #expect(fixture.store.importPreviousStatistics([
            "diagnostics.lastSuccessfulSelectionAt": oldDates.last!,
            "diagnostics.recentVChewingRestoreTimes": oldDates
        ]))
        let snapshot = fixture.store.snapshot
        #expect(snapshot.lastSuccessfulSelection == newest)
        #expect(snapshot.recentVChewingRestores.count == 20)
        #expect(snapshot.recentVChewingRestores.last == newest)
        #expect(snapshot.recentVChewingRestores == snapshot.recentVChewingRestores.sorted())
    }
    @Test func successfulSelectionsAndManualPreservationHaveDistinctCounters() {
        let fixture = StatisticsFixture()
        for i in 0..<25 {
            fixture.store.recordSelectionSuccess(automatic: i < 10, restoredVChewing: true,
                                                at: Date(timeIntervalSince1970: Double(i)))
        }
        fixture.store.recordPreservedExternalSelection()
        fixture.store.recordSecureInputWait()
        #expect(fixture.store.snapshot.automaticCorrections == 10)
        #expect(fixture.store.snapshot.vChewingRestores == 25)
        #expect(fixture.store.snapshot.recentVChewingRestores.count == 20)
        #expect(fixture.store.snapshot.preservedExternalSelections == 1)
        #expect(fixture.store.snapshot.secureInputWaits == 1)
    }
    @Test func damagedStatisticalValuesAreIgnored() {
        let fixture = StatisticsFixture()
        #expect(!fixture.store.importPreviousStatistics([
            "diagnostics.automaticCorrectionCount": -1,
            "diagnostics.failedSelectionCount": "wrong",
            "diagnostics.secureInputWaitCount": true,
            "diagnostics.vChewingRestoreCount": Double.nan,
            "diagnostics.lastSuccessfulSelectionAt": "wrong",
            "diagnostics.recentVChewingRestoreTimes": ["wrong", false]
        ]))
        #expect(fixture.store.snapshot == InputSourceStatistics())
    }
    @Test func countsSaturateInsteadOfOverflowing() {
        let fixture = StatisticsFixture()
        #expect(fixture.store.importPreviousStatistics(["diagnostics.failedSelectionCount": Int.max]))
        fixture.store.recordFailedSelection()
        #expect(fixture.store.snapshot.failedSelections == Int.max)
    }
    @Test func absentPreviousDataDoesNotResetCurrentHistory() {
        let fixture = StatisticsFixture()
        fixture.store.recordPreservedExternalSelection()
        #expect(!fixture.store.importPreviousStatistics(nil))
        #expect(fixture.store.previousStatisticsMigrationCompleted)
        #expect(fixture.store.snapshot.preservedExternalSelections == 1)
        #expect(!fixture.store.importPreviousStatistics(["diagnostics.failedSelectionCount": 5]))
        #expect(fixture.store.snapshot.failedSelections == 0)
    }
}
