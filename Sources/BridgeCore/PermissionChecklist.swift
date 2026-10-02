/// Permission links and successful authorization are separate state transitions.
/// No request/open result or engine cache can produce a verified grant here.
public enum PermissionKind: CaseIterable, Hashable, Sendable {
    case accessibility, posting, listening, screenRecording, finderExtension, loginItem
}

public enum PermissionVerification: Equatable, Sendable {
    case unchecked, awaitingVerification, denied, granted

    public init(verifiedGrant: Bool?) {
        self = verifiedGrant.map { $0 ? .granted : .denied } ?? .unchecked
    }
}

public struct PermissionSnapshot: Equatable, Sendable {
    public var accessibility: Bool
    public var posting: Bool
    public var listening: Bool
    public var screenRecording: Bool
    public var finderExtension: Bool
    public var loginItem: Bool
    /// One settings pane controls keyboard/AX access, but both native capabilities
    /// must be checked. A UI switch or one successful API does not prove the other.
    public var keyboardControlGranted: Bool { accessibility && posting }
    /// Observed after granting the shared system switch in a running process.
    /// This is a restart hint, never proof that the missing capability is granted.
    public var keyboardControlPartiallyGranted: Bool { accessibility != posting }

    public init(accessibility: Bool = false, posting: Bool = false, listening: Bool = false,
                screenRecording: Bool = false, finderExtension: Bool = false, loginItem: Bool = false) {
        self.accessibility = accessibility; self.posting = posting; self.listening = listening
        self.screenRecording = screenRecording; self.finderExtension = finderExtension; self.loginItem = loginItem
    }

    public subscript(_ kind: PermissionKind) -> Bool {
        get {
            switch kind {
            case .accessibility: accessibility
            case .posting: posting
            case .listening: listening
            case .screenRecording: screenRecording
            case .finderExtension: finderExtension
            case .loginItem: loginItem
            }
        }
        set {
            switch kind {
            case .accessibility: accessibility = newValue
            case .posting: posting = newValue
            case .listening: listening = newValue
            case .screenRecording: screenRecording = newValue
            case .finderExtension: finderExtension = newValue
            case .loginItem: loginItem = newValue
            }
        }
    }

    public var diagnosticText: String {
        [("Accessibility", accessibility), ("Event posting", posting),
         ("Input Monitoring", listening), ("Screen Recording", screenRecording),
         ("Finder extension", finderExtension), ("Login item", loginItem)]
            .map { "\($0.0): \($0.1 ? "granted/enabled" : "not granted/disabled")" }
            .joined(separator: "\n")
    }
}

public struct PermissionChecklistState: Equatable, Sendable {
    public private(set) var verified = PermissionSnapshot()
    public private(set) var awaitingVerification: Set<PermissionKind> = []
    private var hasVerifiedSnapshot = false
    public init() {}

    public func verification(for kinds: [PermissionKind]) -> PermissionVerification {
        guard !kinds.isEmpty else { return .unchecked }
        if kinds.contains(where: { awaitingVerification.contains($0) }) { return .awaitingVerification }
        guard hasVerifiedSnapshot else { return .unchecked }
        return kinds.allSatisfy { verified[$0] } ? .granted : .denied
    }

    public mutating func beginNavigation(to kind: PermissionKind) {
        awaitingVerification.insert(kind)
        verified[kind] = false
    }

    /// Only a fresh, read-only native check may confirm or revoke a grant.
    public mutating func verify(_ snapshot: PermissionSnapshot) {
        verified = snapshot
        hasVerifiedSnapshot = true
        awaitingVerification.removeAll()
    }
}
