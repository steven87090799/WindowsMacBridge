/// Metadata only: no URLs, file names, text or pasteboard payloads are retained.
public struct FinderCutState: Sendable {
    private struct Intent: Sendable {
        let changeCount: Int
        let finderPID: Int32
        let expiresAt: Double
    }
    private var intent: Intent?
    public init() {}
    public mutating func cancel() { intent = nil }
    public mutating func arm(changeCount: Int, finderPID: Int32, now: Double) {
        intent = Intent(changeCount: changeCount, finderPID: finderPID, expiresAt: now + 300)
    }
    public mutating func validate(changeCount: Int, finderPID: Int32, now: Double) -> Bool {
        guard let intent else { return false }
        guard intent.changeCount == changeCount, intent.finderPID == finderPID,
              now < intent.expiresAt else { cancel(); return false }
        return true
    }
    /// Consumed when a move is requested, not when a move is claimed successful.
    public mutating func consume(changeCount: Int, finderPID: Int32, now: Double) -> Bool {
        let valid = validate(changeCount: changeCount, finderPID: finderPID, now: now)
        cancel()
        return valid
    }
}
