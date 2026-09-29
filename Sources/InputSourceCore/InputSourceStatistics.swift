// Statistics fields adapted from vchewing-input-helper @ 43779320 (MIT).
// See Resources/Licenses/VChewingGuard.txt.
import Foundation
import CoreFoundation

public struct InputSourceStatistics: Equatable, Sendable {
    public var automaticCorrections = 0
    public var failedSelections = 0
    public var secureInputWaits = 0
    public var vChewingRestores = 0
    public var preservedExternalSelections = 0
    public var lastSuccessfulSelection: Date?
    public var recentVChewingRestores: [Date] = []
    public var previousStatisticsImported = false
    public init() {}
}

/// Low-frequency counters only; no keyboard data and at most 20 timestamps.
public final class InputSourceStatisticsStore {
    private let defaults: UserDefaults
    private let prefix = "inputSource.diagnostics."
    private let maximumRecentTimes = 20
    private let migrationKey = "inputSource.diagnostics.previousStatisticsMigrationCompleted"
    private let importedKey = "inputSource.diagnostics.previousStatisticsImported"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var previousStatisticsMigrationCompleted: Bool { defaults.bool(forKey: migrationKey) }

    public var snapshot: InputSourceStatistics {
        var result = InputSourceStatistics()
        result.automaticCorrections = count("automaticCorrectionCount")
        result.failedSelections = count("failedSelectionCount")
        result.secureInputWaits = count("secureInputWaitCount")
        result.vChewingRestores = count("vChewingRestoreCount")
        result.preservedExternalSelections = count("preservedExternalSelectionCount")
        result.lastSuccessfulSelection = Self.validDate(defaults.object(forKey: prefix + "lastSuccessfulSelectionAt"))
        result.recentVChewingRestores = recentTimes
        result.previousStatisticsImported = defaults.bool(forKey: importedKey)
        return result
    }

    /// Import only the six statistical fields, once. Existing bridge counters
    /// are added, dates are merged, and all settings/other legacy data are ignored.
    @discardableResult public func importPreviousStatistics(_ previous: [String: Any]?) -> Bool {
        guard !previousStatisticsMigrationCompleted else { return false }
        let previous = previous ?? [:]
        var imported = false
        for name in ["automaticCorrectionCount", "failedSelectionCount", "secureInputWaitCount", "vChewingRestoreCount"] {
            let raw = previous["diagnostics." + name]
            guard Self.isValidCount(raw) else { continue }
            defaults.set(Self.add(count(name), Self.boundedCount(raw)), forKey: prefix + name)
            imported = true
        }
        if let oldDate = Self.validDate(previous["diagnostics.lastSuccessfulSelectionAt"]) {
            let current = snapshot.lastSuccessfulSelection
            defaults.set(max(current ?? oldDate, oldDate), forKey: prefix + "lastSuccessfulSelectionAt")
            imported = true
        }
        let oldTimes = Self.dates(previous["diagnostics.recentVChewingRestoreTimes"], limit: maximumRecentTimes)
        if !oldTimes.isEmpty {
            let merged = Array(Set(recentTimes + oldTimes)).sorted().suffix(maximumRecentTimes)
            defaults.set(Array(merged), forKey: prefix + "recentVChewingRestoreTimes")
            imported = true
        }
        defaults.set(imported, forKey: importedKey)
        defaults.set(true, forKey: migrationKey)
        return imported
    }

    public func recordSelectionSuccess(automatic: Bool, restoredVChewing: Bool, at date: Date) {
        defaults.set(date, forKey: prefix + "lastSuccessfulSelectionAt")
        if automatic { increment("automaticCorrectionCount") }
        if restoredVChewing {
            increment("vChewingRestoreCount")
            defaults.set(Array((recentTimes + [date]).suffix(maximumRecentTimes)),
                         forKey: prefix + "recentVChewingRestoreTimes")
        }
    }

    public func recordFailedSelection() { increment("failedSelectionCount") }
    public func recordSecureInputWait() { increment("secureInputWaitCount") }
    public func recordPreservedExternalSelection() { increment("preservedExternalSelectionCount") }

    private var recentTimes: [Date] {
        Self.dates(defaults.object(forKey: prefix + "recentVChewingRestoreTimes"), limit: maximumRecentTimes)
    }
    private func count(_ name: String) -> Int { Self.boundedCount(defaults.object(forKey: prefix + name)) }
    private func increment(_ name: String) { defaults.set(Self.add(count(name), 1), forKey: prefix + name) }
    private static func add(_ lhs: Int, _ rhs: Int) -> Int { lhs > Int.max - rhs ? Int.max : lhs + rhs }
    private static func isValidCount(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue.isFinite && number.doubleValue >= 0
    }
    private static func boundedCount(_ value: Any?) -> Int {
        guard isValidCount(value), let number = value as? NSNumber else { return 0 }
        return number.doubleValue >= Double(Int.max) ? Int.max : Int(number.doubleValue)
    }
    private static func validDate(_ value: Any?) -> Date? {
        guard let date = value as? Date, date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }
    private static func dates(_ value: Any?, limit: Int) -> [Date] {
        (value as? [Any] ?? []).suffix(limit).compactMap(validDate)
    }
}
