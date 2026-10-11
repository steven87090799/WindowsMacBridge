/// App-sensitive rules need evidence that WindowServer selected a local recipient.
/// Source PID, the source Mac's foreground App and a HID service are not delivery evidence.
public enum DestinationSemanticPolicy {
    public static func acceptsDelivery(target: Int32, foreground: Int32) -> Bool {
        target > 0 && foreground > 0 && target == foreground
    }
    /// Region/display screenshots belong to the receiving Mac, not to an App.
    /// A menu-bar panel can receive the annotated event while another App remains
    /// frontmost. A positive recipient still supplies local delivery evidence;
    /// an absent recipient must not start capture on a Universal Control source.
    /// Active-window capture retains the stricter foreground ownership check.
    public static func acceptsScreenshotDelivery(target: Int32, foreground: Int32,
                                                  kind: ScreenshotKind) -> Bool {
        if kind == .activeWindow { return acceptsDelivery(target: target, foreground: foreground) }
        return target > 0 && foreground > 0
    }
    public static func acceptsKeyDown(target: Int32, foreground: Int32, key: UInt16, nativeTabHeld: Bool) -> Bool {
        acceptsDelivery(target: target, foreground: foreground) ||
            (target == 0 && foreground > 0 && key == 48 && nativeTabHeld)
    }
}
