import ApplicationServices

/// On-demand worker work only. Never reads text, values, selection or clipboard.
enum TextNavigationFocusReader {
    static func isTextRole(_ role: String) -> Bool {
        role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
    }
    static func read(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.03)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let focused = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.03)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return false }
        guard isTextRole(role) else { return false }
        if role == kAXComboBoxRole {
            // A non-editable ARIA combobox is not a text field. Query capability
            // metadata only; never read its value or selected text.
            var editable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &editable) == .success && editable.boolValue
        }
        return true
    }
}
