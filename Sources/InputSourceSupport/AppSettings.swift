// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Carbon
import Foundation
import InputSourceCore

enum AppSettings {
    private static let defaults = UserDefaults.standard

    static let debounceKey = "inputSource.debounceMilliseconds"
    static let startupDelayKey = "inputSource.startupDelayMilliseconds"
    static let hotkeyKey = "inputSource.hotkeyPreset"
    static let guardEnabledKey = "inputSource.guardEnabled"
    static let pauseDurationKey = "inputSource.pauseDuration"
    static let pauseUntilKey = "inputSource.pauseUntil"
    static let pauseIndefiniteKey = "inputSource.pauseIndefinite"

    static func registerDefaults() {
        defaults.register(defaults: [
            debounceKey: 400,
            startupDelayKey: 1_500,
            hotkeyKey: HotkeyPreset.controlOptionCommandSpace.rawValue,
            guardEnabledKey: false,
            pauseDurationKey: GuardPauseDuration.fifteenMinutes.rawValue,
        ])
    }

    static var debounceMilliseconds: Int {
        min(1_200, max(200, defaults.integer(forKey: debounceKey)))
    }

    static var startupDelayMilliseconds: Int {
        min(5_000, max(0, defaults.integer(forKey: startupDelayKey)))
    }

    static var guardEnabled: Bool { defaults.bool(forKey: guardEnabledKey) }

    static var pauseDuration: GuardPauseDuration {
        GuardPauseDuration(rawValue: defaults.string(forKey: pauseDurationKey) ?? "") ?? .fifteenMinutes
    }

    static var detectionPause: GuardDetectionPause {
        GuardDetectionPause(until: defaults.object(forKey: pauseUntilKey) as? Date,
                            indefinite: defaults.bool(forKey: pauseIndefiniteKey))
    }

    static func setPauseDuration(_ value: GuardPauseDuration) {
        defaults.set(value.rawValue, forKey: pauseDurationKey)
    }

    static func setDetectionPause(_ value: GuardDetectionPause) {
        if let until = value.until { defaults.set(until, forKey: pauseUntilKey) }
        else { defaults.removeObject(forKey: pauseUntilKey) }
        defaults.set(value.indefinite, forKey: pauseIndefiniteKey)
    }

    static var hotkeyPreset: HotkeyPreset {
        HotkeyPreset(rawValue: defaults.string(forKey: hotkeyKey) ?? "") ?? .controlOptionCommandSpace
    }

    static func setDebounce(_ milliseconds: Int) {
        defaults.set(min(1_200, max(200, milliseconds)), forKey: debounceKey)
    }

    static func setStartupDelay(_ milliseconds: Int) {
        defaults.set(min(5_000, max(0, milliseconds)), forKey: startupDelayKey)
    }

    static func setGuardEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: guardEnabledKey)
    }

    static func setHotkeyPreset(_ preset: HotkeyPreset) {
        defaults.set(preset.rawValue, forKey: hotkeyKey)
    }
}

public enum HotkeyPreset: String, CaseIterable, Sendable {
    case controlOptionCommandSpace
    case controlOptionShiftSpace
    case controlCommandSpace
    case optionCommandSpace

    public var title: String {
        switch self {
        case .controlOptionCommandSpace: "⌃ ⌥ ⌘ Space（預設）"
        case .controlOptionShiftSpace: "⌃ ⌥ ⇧ Space"
        case .controlCommandSpace: "⌃ ⌘ Space"
        case .optionCommandSpace: "⌥ ⌘ Space"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionCommandSpace: UInt32(controlKey | optionKey | cmdKey)
        case .controlOptionShiftSpace: UInt32(controlKey | optionKey | shiftKey)
        case .controlCommandSpace: UInt32(controlKey | cmdKey)
        case .optionCommandSpace: UInt32(optionKey | cmdKey)
        }
    }

    var eventKeyCode: UInt32 { UInt32(kVK_Space) }
}
