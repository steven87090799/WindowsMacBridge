import Carbon

public enum KeyboardLayoutResolver {
    public static func supports(sourceID: String, asciiLayoutID: String, allowIME: Bool) -> Bool {
        let ascii = ["com.apple.keylayout.US", "com.apple.keylayout.ABC"]
        if ascii.contains(sourceID) { return true }
        // An explicit physical-key option, not a claim that composition state is known.
        return allowIME && !sourceID.isEmpty && sourceID != "unknown" && ascii.contains(asciiLayoutID)
    }
    public static func current(allowIME: Bool = false) -> (id: String, supported: Bool) {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ("unknown", false)
        }
        let identifier = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        var asciiID = ""
        if let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(ascii, kTISPropertyInputSourceID) {
            asciiID = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        }
        return (identifier, supports(sourceID: identifier, asciiLayoutID: asciiID, allowIME: allowIME))
    }
}
