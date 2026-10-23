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
        // A positive annotated target proves local delivery even for a panel
        // that does not activate its owner. Its identity is resolved separately.
        target > 0 ||
            (target == 0 && foreground > 0 && key == 48 && nativeTabHeld)
    }

    /// System panels can own keyboard focus while a different App remains
    /// frontmost. Select rules for the actual recipient; never borrow Finder or
    /// Terminal actions from the App underneath that panel.
    public static func context(target: Int32, foreground: ApplicationContext,
                               recipients: [Int32: ApplicationContext]) -> ApplicationContext? {
        guard target > 0 else { return nil }
        if target == foreground.processID { return foreground }
        if let known = recipients[target] { return known }
        // WindowServer already selected a local recipient. A just-created
        // system service need not be in NSWorkspace's launch snapshot yet.
        // Permit only native clipboard keys until its identity is resolved.
        var fallback = ApplicationContext(processID: target, displayName: "本機視窗", mode: .macOS)
        fallback.clipboardOnly = true
        return fallback
    }
}
