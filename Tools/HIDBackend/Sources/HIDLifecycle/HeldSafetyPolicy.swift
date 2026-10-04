/// One-shot loss guard for captured input. Neutral idle has no deadline at all.
/// While anything could be left pressed on the virtual devices (held keys,
/// modifiers, pointing buttons) or reports have not been completed by the
/// driver (including a final key-up or button-up), a single deadline makes the
/// capture re-check driver progress; a stalled driver then fails closed.
public enum HeldSafetyPolicy {
    /// Re-check soon after the VirtualHID stall threshold (500 ms) can trip.
    public static let outstandingDeadline = 0.6
    public static let heldDeadline = 1.0
    public static func deadline(capturing: Bool, heldOutput: Bool, pointingButtons: UInt32,
                                outstandingReports: UInt32) -> Double? {
        guard capturing else { return nil }
        if outstandingReports > 0 { return outstandingDeadline }
        if heldOutput || pointingButtons != 0 { return heldDeadline }
        return nil
    }
}
