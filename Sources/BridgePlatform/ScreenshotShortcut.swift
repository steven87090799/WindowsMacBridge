import Foundation
import CoreGraphics
import BridgeCore

/// Only the physical S key with exactly the configured Win modifier and Shift is claimed. The
/// corresponding key-up is consumed even if the modifiers were released first.
public struct ScreenshotShortcut: Sendable {
    public static let keyCode: UInt16 = 1
    private var pressed: UInt8 = 0
    public var captureKind: ScreenshotKind = .region
    public var printScreenBehavior: PrintScreenBehavior = .snipping
    public var windowsKeyModifier: WindowsKeyModifier
    public init(windowsKeyModifier: WindowsKeyModifier = .option) {
        self.windowsKeyModifier = windowsKeyModifier
    }

    public mutating func reset() { pressed = 0 }
    public static func supports(_ key: UInt16) -> Bool { key == keyCode || key == 105 }

    /// The same native event adapter used by the screenshot tap and regression tests.
    public mutating func handle(type: CGEventType, event: CGEvent, allowsCapture: Bool = true) -> ScreenshotDecision {
        // Check provenance before touching the held-key ledger, including key-up.
        // Event taps may be recreated in either order after permission/session recovery.
        guard !EventRewriter.isGeneratedByBridge(event) else { return .passThrough }
        guard type == .keyDown || type == .keyUp else { return .passThrough }
        if type == .keyDown && !allowsCapture { return .passThrough }
        let flags = event.flags
        return handle(keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                      isDown: type == .keyDown,
                      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                      command: flags.contains(.maskCommand), shift: flags.contains(.maskShift),
                      option: flags.contains(.maskAlternate), control: flags.contains(.maskControl))
    }

    public mutating func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool,
                                command: Bool, shift: Bool, option: Bool, control: Bool) -> ScreenshotDecision {
        guard Self.supports(keyCode) else { return .passThrough }
        let bit: UInt8 = keyCode == Self.keyCode ? 1 : 2
        if !isDown {
            guard pressed & bit != 0 else { return .passThrough }
            pressed &= ~bit
            return .suppress
        }
        if pressed & bit != 0 && isRepeat { return .suppress }
        // A non-repeat down after a lost key-up starts a fresh chord.
        pressed &= ~bit
        var flags: Modifiers = []
        if command { flags.insert(.command) }; if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }; if control { flags.insert(.control) }
        guard !isRepeat, let kind = WindowsScreenshotShortcuts.match(key: keyCode, modifiers: flags,
            windowsKey: windowsKeyModifier, printScreen: printScreenBehavior) else { return .passThrough }
        captureKind = kind
        pressed |= bit
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
