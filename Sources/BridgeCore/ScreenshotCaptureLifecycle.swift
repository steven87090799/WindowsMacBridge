/// One user-requested capture at a time. A toggle or shutdown invalidates its
/// clipboard write without pretending the native capture process has finished.
public struct ScreenshotCaptureLifecycle: Sendable {
    public struct Token: Equatable, Sendable {
        fileprivate let sequence: UInt64
        fileprivate let revision: UInt64
    }
    private var enabled = false
    private var revision: UInt64 = 0
    private var sequence: UInt64 = 0
    private var active: Token?
    public init() {}
    public mutating func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        revision &+= 1
    }
    public mutating func begin() -> Token? {
        guard enabled, active == nil else { return nil }
        sequence &+= 1
        let token = Token(sequence: sequence, revision: revision)
        active = token
        return token
    }
    public func isCurrent(_ token: Token) -> Bool {
        enabled && active == token && token.revision == revision
    }
    /// Returns whether this completion may write to Clipboard. Stale completions
    /// cannot clear a newer capture, and disabled captures cannot overlap a new one.
    public mutating func complete(_ token: Token) -> Bool {
        guard active == token else { return false }
        let valid = isCurrent(token)
        active = nil
        return valid
    }
}
