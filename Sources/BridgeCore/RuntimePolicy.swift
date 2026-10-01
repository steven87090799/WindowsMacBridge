public enum InputBackend: String, Codable, CaseIterable, Sendable {
    case deviceHID, eventTap
    public var title: String { self == .deviceHID ? "裝置 HID 後端（需要 helper）" : "CGEventTap 快捷鍵" }
}

/// Foreground application classification describes a client, not the origin of incoming input.
/// Choose the receiving role manually when the transport does not preserve provenance.
public enum RemoteInputProfile: String, Codable, CaseIterable, Sendable {
    case automatic, windowsReceiver, macReceiver, alreadyTranslated, sourcePassThrough
    public var translates: Bool { self == .automatic || self == .windowsReceiver }
    public var title: String {
        switch self {
        case .automatic: "本機／依 App 規則"
        case .windowsReceiver: "接收原始 Windows 按鍵（此端轉譯）"
        case .macReceiver: "接收原生 Mac 按鍵（原樣通過）"
        case .alreadyTranslated: "來源已有 Bridge（此端原樣通過）"
        case .sourcePassThrough: "傳送／通用控制來源（原樣通過）"
        }
    }
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
    public var remoteProfile: RemoteInputProfile = .automatic
    public var paused = false, secureInput = false, sessionActive = true, manualPassThrough = false
    public var session: UInt64 = 0
    public var screenshotEnabled = false, shortcutEnabled = false
    public var settingsRevision: UInt64 = 0
    public var restartToken: UInt64 = 0
    public var accessibility = true, posting = true
    public var hidReleasePending = false
    public var layoutIdentity = ""
    public var layoutSupported = true, diagnosticsEnabled = false, nativeRestorePending = false
    public init() {}
}
/// Value snapshot copied at transitions; callback code never queries UI or AX to derive policy.
public struct RuntimePolicySnapshot: Equatable, Sendable {
    public let input: RuntimePolicyInput
    public let generation: UInt64
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
        input.shortcutEnabled && !input.hidReleasePending && !input.paused && !input.secureInput && input.sessionActive &&
            (input.remoteProfile.translates || input.remoteProfile == .sourcePassThrough) && input.accessibility && input.posting
    }
    public var permitsInput: Bool {
        input.shortcutEnabled && !input.hidReleasePending && !input.paused && !input.secureInput && input.sessionActive &&
            input.remoteProfile.translates && input.accessibility && input.posting
    }
    public var permitsScreenshots: Bool {
        permitsShortcuts && input.screenshotEnabled && input.foreground.mode == .macOS
    }
}
public struct RuntimePolicyCoordinator: Sendable {
    public private(set) var current: RuntimePolicySnapshot?
    private var generation: UInt64 = 0
    public init() {}
    public mutating func transition(_ input: RuntimePolicyInput) -> RuntimePolicySnapshot {
        if let current, current.input == input { return current }
        generation &+= 1
        let next = RuntimePolicySnapshot(input: input, generation: generation)
        current = next
        return next
    }
}

/// UI/status observation stops when input is intentionally inactive. Explicit pause/debug
/// deadlines remain one-shot; a mapping waiting for neutral reuses the existing 1s check.
public enum RuntimeWakePlan: Equatable, Sendable {
    case stopped, periodic, deadline(Double)
    public static func make(input: RuntimePolicyInput, awaitingMappingNeutral: Bool,
                            deadline: Double?) -> Self {
        if awaitingMappingNeutral || (input.shortcutEnabled && !input.paused && input.sessionActive && input.remoteProfile.translates) {
            return .periodic
        }
        return deadline.map(Self.deadline) ?? .stopped
    }
}
