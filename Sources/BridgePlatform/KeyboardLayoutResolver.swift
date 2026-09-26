import Carbon

public enum KeyboardLayoutResolver {
    /// An IME is deliberately unsupported even if its underlying ASCII layout is US.
    /// This avoids remapping shortcuts inside an unknown composition state.
    public static func current() -> (id: String, supported: Bool) {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ("unknown", false)
        }
        let identifier = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return (identifier, identifier == "com.apple.keylayout.US" || identifier == "com.apple.keylayout.ABC")
    }
}
