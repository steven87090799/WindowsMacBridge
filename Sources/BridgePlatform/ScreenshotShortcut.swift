import Foundation

/// Only the physical S key with exactly Command (Win on a PC keyboard) and Shift is claimed. The
/// corresponding key-up is consumed even if the modifiers were released first.
public struct ScreenshotShortcut: Sendable {
    public static let keyCode: UInt16 = 1
    private var pressed = false
    public init() {}

    public mutating func reset() { pressed = false }

    public mutating func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool,
                                command: Bool, shift: Bool, option: Bool, control: Bool) -> ScreenshotDecision {
        guard keyCode == Self.keyCode else { return .passThrough }
        if !isDown {
            guard pressed else { return .passThrough }
            pressed = false
            return .suppress
        }
        if pressed && isRepeat { return .suppress }
        // A non-repeat down after a lost key-up starts a fresh chord.
        if pressed { pressed = false }
        guard !isRepeat, command, shift, !option, !control else { return .passThrough }
        pressed = true
        return .capture
    }
}

public enum ScreenshotDecision: Equatable, Sendable {
    case passThrough, suppress, capture
}

public enum ScreenshotCheckSchedule {
    public static let interval: TimeInterval = 30 * 24 * 60 * 60
    public static func delay(lastCheck: Date?, now: Date) -> TimeInterval {
        guard let lastCheck else { return interval }
        return min(interval, max(1, lastCheck.addingTimeInterval(interval).timeIntervalSince(now)))
    }
}
