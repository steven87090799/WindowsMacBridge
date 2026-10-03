public enum InputBackend: String, Codable, CaseIterable, Sendable {
    case deviceHID, eventTap
    public var title: String { self == .deviceHID ? "裝置 HID 後端（需要 helper）" : "CGEventTap 快捷鍵" }
}

public enum KeyboardOwnership {
    public enum Owner: Sendable { case hid, eventTap, native }
    /// There is no reliable device ID in a public session EventTap. Never run a blind hybrid.
    public static func owner(backend: InputBackend, seized: Bool) -> Owner {
        backend == .eventTap ? .eventTap : (seized ? .hid : .native)
    }
}
public struct RuntimePolicyInput: Equatable, Sendable {
    public var backend: InputBackend = .eventTap
    public var deviceScope: KeyboardScope = .allKeyboards
    public var foreground = ApplicationContext()
    public var paused = false, secureInput = false, sessionActive = true, manualPassThrough = false
    public var session: UInt64 = 0
    public var screenshotEnabled = false, shortcutEnabled = false
    public var settingsRevision: UInt64 = 0
    public var restartToken: UInt64 = 0
    public var accessibility = true, posting = true, listening = true
    public var loginItemEnabled = true
    public var hidReleasePending = false
    public var layoutIdentity = ""
    public var layoutSupported = true, diagnosticsEnabled = false, nativeRestorePending = false
    public init() {}
}
/// Value snapshot copied at transitions; callback code never queries UI or AX to derive policy.
public struct RuntimePolicySnapshot: Equatable, Sendable {
    public let input: RuntimePolicyInput
    public let generation: UInt64
    /// Changes at lifecycle/settings/ownership gaps, even when the input mailbox
    /// coalesces several transitions into one delivered configuration.
    public let modifierEpoch: UInt64
    /// TIS publishes its own layout change during a selection. Its work epoch follows
    /// host lifecycle/settings, without cancelling itself on that acknowledgement.
    public var sourceWorkPolicy: RuntimePolicyInput {
        var value = input; value.layoutIdentity = ""; value.layoutSupported = true
        return value
    }
    public var permitsShortcuts: Bool {
        permitsInput && !input.manualPassThrough
    }
    public var permitsPhysicalNormalization: Bool {
        permitsInput && !input.manualPassThrough
    }
    public var permitsInput: Bool {
        input.shortcutEnabled && (input.backend == .eventTap || !input.hidReleasePending) && !input.paused && !input.secureInput && input.sessionActive &&
            input.accessibility && input.posting && input.listening
    }
    public var permitsScreenshots: Bool {
        permitsShortcuts && input.screenshotEnabled &&
            (input.foreground.mode == .macOS || input.foreground.mode == .terminal || input.foreground.mode == .ide ||
             (input.foreground.mode == .disabled && input.foreground.bundleID == "local.WindowsMacBridge"))
    }
    /// Several foreground changes may coalesce; a pause/session/security gap is
    /// retained in modifierEpoch and must still force a neutral handoff.
    public func preservesModifiers(from previous: Self) -> Bool {
        guard generation != previous.generation, modifierEpoch == previous.modifierEpoch,
              permitsShortcuts, previous.permitsShortcuts,
              input.layoutSupported, !input.nativeRestorePending,
              input.foreground.processID > 0, previous.input.foreground.processID > 0,
              Self.hasContinuousKeyboardOwnership(input.foreground.mode),
              Self.hasContinuousKeyboardOwnership(previous.input.foreground.mode) else { return false }
        var normalized = input; normalized.foreground = previous.input.foreground
        return normalized == previous.input
    }
    private static func hasContinuousKeyboardOwnership(_ mode: ApplicationMode) -> Bool {
        mode == .macOS || mode == .terminal || mode == .ide
    }
}
public struct RuntimePolicyCoordinator: Sendable {
    public private(set) var current: RuntimePolicySnapshot?
    private var generation: UInt64 = 0
    private var modifierEpoch: UInt64 = 0
    public init() {}
    public mutating func transition(_ input: RuntimePolicyInput) -> RuntimePolicySnapshot {
        if let current, current.input == input { return current }
        generation &+= 1
        let candidate = RuntimePolicySnapshot(input: input, generation: generation, modifierEpoch: modifierEpoch)
        if current.map({ candidate.preservesModifiers(from: $0) }) != true { modifierEpoch &+= 1 }
        let next = RuntimePolicySnapshot(input: input, generation: generation, modifierEpoch: modifierEpoch)
        current = next
        return next
    }
}

/// Explicit pause/debug deadlines are one-shot. Input and mapping transitions
/// use key and lifecycle notifications; active-but-neutral input never polls.
public enum RuntimeWakePlan: Equatable, Sendable {
    case stopped, deadline(Double)
    public static func make(input: RuntimePolicyInput, awaitingMappingNeutral: Bool,
                            deadline: Double?) -> Self {
        // Key edges/lifecycle notifications drive maintenance; no idle polling.
        return deadline.map(Self.deadline) ?? .stopped
    }
}
