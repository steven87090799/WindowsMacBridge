import BridgeWorkGate

/// A native Ctrl+C must cancel a pending file cut immediately, even while the
/// main actor is busy. Only revision numbers cross threads, never file data.
public final class FinderClipboardIntent: @unchecked Sendable {
    private let storage: OpaquePointer
    public init() {
        guard let value = WMBClipboardIntentCreate() else { preconditionFailure("Clipboard intent allocation failed") }
        storage = value
    }
    deinit { WMBClipboardIntentDestroy(storage) }
    public func observeCopy() { WMBClipboardIntentCopy(storage) }
    public func beginCut() -> UInt64 { WMBClipboardIntentCut(storage) }
    public var pending: UInt64 { WMBClipboardIntentPending(storage) }
    public func isCurrent(_ ticket: UInt64) -> Bool { WMBClipboardIntentIsCurrent(storage, ticket) }
    public func finish(_ ticket: UInt64) { WMBClipboardIntentFinish(storage, ticket) }
}
