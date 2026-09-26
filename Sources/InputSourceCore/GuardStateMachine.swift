// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Foundation

public enum DesiredInputSource: String, Equatable, Sendable {
    case vChewing
    case abc
}

public enum ObservedInputSource: Equatable, Sendable {
    case vChewing
    case abc
    case other
}

public enum SourceChangeResponse: Equatable, Sendable {
    case ignored
    case alreadySatisfied
    case scheduleDebounce(milliseconds: Int)
}

/// The small, deterministic policy core. All macOS event handling and TIS calls
/// live in the app target; this type makes desired-state and retry rules testable.
public struct GuardStateMachine: Sendable {
    public private(set) var desired: DesiredInputSource = .vChewing
    public private(set) var isEnabled: Bool
    public private(set) var debounceMilliseconds: Int
    public let maximumSelectionAttempts: Int
    private(set) var selectionAttempts = 0
    private var hasMismatchTransaction = false

    public init(
        isEnabled: Bool = true,
        debounceMilliseconds: Int = 400,
        maximumSelectionAttempts: Int = 3
    ) {
        self.isEnabled = isEnabled
        self.debounceMilliseconds = max(0, debounceMilliseconds)
        self.maximumSelectionAttempts = max(1, maximumSelectionAttempts)
    }

    /// A Guard hotkey or menu command is an explicit user request.
    @discardableResult
    public mutating func toggleDesiredSource() -> DesiredInputSource {
        request(desired == .vChewing ? .abc : .vChewing)
    }

    @discardableResult
    public mutating func request(_ source: DesiredInputSource) -> DesiredInputSource {
        desired = source
        selectionAttempts = 0
        hasMismatchTransaction = true
        return desired
    }

    /// Resuming deliberately restores vChewing priority; the last ABC choice is
    /// never persisted across app launches or a Guard pause/resume cycle.
    public mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        selectionAttempts = 0
        hasMismatchTransaction = false
        if enabled {
            desired = .vChewing
        }
    }

    public mutating func setDebounce(milliseconds: Int) {
        debounceMilliseconds = max(0, milliseconds)
    }

    public mutating func observe(
        _ current: ObservedInputSource,
        isInternalSwitch: Bool
    ) -> SourceChangeResponse {
        guard isEnabled, !isInternalSwitch else { return .ignored }
        guard current != desired.observedSource else {
            selectionAttempts = 0
            hasMismatchTransaction = false
            return .alreadySatisfied
        }
        selectionAttempts = 0
        hasMismatchTransaction = true
        return .scheduleDebounce(milliseconds: debounceMilliseconds)
    }

    /// Returns the 1-based attempt number, or nil once the bounded retry budget
    /// is exhausted. Delays after attempt one follow 400, 800, 1600 ms.
    public mutating func beginSelectionAttempt() -> Int? {
        guard isEnabled, hasMismatchTransaction, selectionAttempts < maximumSelectionAttempts else { return nil }
        selectionAttempts += 1
        return selectionAttempts
    }

    public func delayBeforeNextAttempt() -> Int? {
        guard isEnabled, hasMismatchTransaction, selectionAttempts > 0, selectionAttempts < maximumSelectionAttempts else { return nil }
        let exponent = max(0, selectionAttempts)
        let multiplier = 1 << min(exponent, 10)
        return debounceMilliseconds * multiplier
    }

    public mutating func selectionSucceeded() {
        selectionAttempts = 0
        hasMismatchTransaction = false
    }
}

private extension DesiredInputSource {
    var observedSource: ObservedInputSource {
        switch self {
        case .vChewing: .vChewing
        case .abc: .abc
        }
    }
}
