import Foundation

public enum GuardPauseDuration: String, CaseIterable, Sendable {
    case fiveMinutes, fifteenMinutes, thirtyMinutes, oneHour, untilResumed

    public var title: String {
        switch self {
        case .fiveMinutes: "5 分鐘"
        case .fifteenMinutes: "15 分鐘"
        case .thirtyMinutes: "30 分鐘"
        case .oneHour: "1 小時"
        case .untilResumed: "直到手動恢復"
        }
    }

    public var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1_800
        case .oneHour: 3_600
        case .untilResumed: nil
        }
    }
}

/// Absolute expiry survives app updates and sleep. The adapter schedules one
/// recovery callback; no countdown or polling is needed.
public struct GuardDetectionPause: Equatable, Sendable {
    public var until: Date?
    public var indefinite: Bool

    public init(until: Date? = nil, indefinite: Bool = false) {
        self.until = until
        self.indefinite = indefinite
    }

    public init(duration: GuardPauseDuration, now: Date) {
        until = duration.seconds.map { now.addingTimeInterval($0) }
        indefinite = duration == .untilResumed
    }

    public func isActive(at date: Date) -> Bool {
        indefinite || (until.map { $0 > date } ?? false)
    }
}
