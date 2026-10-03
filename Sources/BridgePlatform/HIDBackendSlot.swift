import Foundation

/// Owns the active HID client and every client still retiring a capture lease.
///
/// Leaving HID used to drop the client immediately: its stop request and
/// deadline were destroyed with it, and the EventTap started while the root
/// service could still hold the keyboard and emit translated VirtualHID output
/// (pid 0, HID state) back into the session tap. A retiring client now stays
/// alive until its bounded stop resolves (acknowledgement, invalidation or the
/// client's own stop deadline), and `releasePending` gates every new owner.
/// A deadline without acknowledgement fails closed until an explicit restart.
@MainActor public final class HIDBackendSlot {
    public private(set) var active: HIDBackendClient?
    private var retiring: [HIDBackendClient] = []
    /// Latched from a retired client whose stop timed out (see HIDBackendClient).
    private var unconfirmed = false
    /// New clients cannot connect while a release is pending, so one retiring
    /// client is the steady state. The bound only protects against misuse.
    static let retiringLimit = 4
    private let factory: @MainActor () -> HIDBackendClient
    /// Called after any client's ownership changes, including a retiring stop.
    public var onOwnershipChange: (() -> Void)?

    public init(factory: @escaping @MainActor () -> HIDBackendClient = { HIDBackendClient() }) {
        self.factory = factory
    }

    /// True while any client this App created may still own a physical keyboard.
    /// An unacknowledged stop fails closed until `clearUnconfirmedRelease()`.
    public var releasePending: Bool {
        active?.releasePending == true || retiring.contains { $0.releasePending } || releaseUnconfirmed
    }
    public var releaseUnconfirmed: Bool { unconfirmed || active?.releaseUnconfirmed == true }
    /// Explicit user restart only: the user has confirmed the keyboard state.
    public func clearUnconfirmedRelease() {
        unconfirmed = false
        active?.clearUnconfirmedRelease()
    }
    public var retiringCount: Int { retiring.count }

    /// Creates or retires the active client. Returns true when it changed.
    @discardableResult public func synchronize(wanted: Bool) -> Bool {
        reap()
        if wanted {
            guard active == nil else { return false }
            let client = factory()
            client.onOwnershipChange = { [weak self] in self?.ownershipChanged() }
            active = client
            client.start()
            return true
        }
        guard let client = active else { return false }
        active = nil
        if client.releaseUnconfirmed { unconfirmed = true }
        // The caller is already applying a transition; do not re-enter it while
        // the stop request is being issued.
        client.onOwnershipChange = nil
        client.releaseOwnership()
        if client.releasePending {
            if retiring.count >= Self.retiringLimit {
                // Evicting a still-pending stop abandons its acknowledgement: fail closed.
                let oldest = retiring.removeFirst()
                if oldest.releasePending || oldest.releaseUnconfirmed { unconfirmed = true }
                oldest.onOwnershipChange = nil; oldest.stop()
            }
            client.onOwnershipChange = { [weak self] in self?.ownershipChanged() }
            retiring.append(client)
        } else {
            client.stop()
        }
        return true
    }

    /// App termination: request every stop; process exit invalidates the rest.
    public func stopAll() {
        for client in retiring { client.onOwnershipChange = nil; client.stop() }
        retiring.removeAll()
        active?.onOwnershipChange = nil
        active?.stop(); active = nil
    }

    private func ownershipChanged() {
        reap()
        onOwnershipChange?()
    }

    private func reap() {
        retiring.removeAll { client in
            guard !client.releasePending else { return false }
            if client.releaseUnconfirmed { unconfirmed = true }
            client.onOwnershipChange = nil
            client.stop()
            return true
        }
    }
}
