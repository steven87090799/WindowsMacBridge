/// App-sensitive rules need evidence that WindowServer selected a local recipient.
/// Source PID, the source Mac's foreground App and a HID service are not delivery evidence.
public enum DestinationSemanticPolicy {
    public static func acceptsDelivery(target: Int32, foreground: Int32) -> Bool {
        target > 0 && foreground > 0 && target == foreground
    }
    public static func acceptsKeyDown(target: Int32, foreground: Int32, key: UInt16, nativeTabHeld: Bool) -> Bool {
        acceptsDelivery(target: target, foreground: foreground) ||
            (target == 0 && foreground > 0 && key == 48 && nativeTabHeld)
    }
}
