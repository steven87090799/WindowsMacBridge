import Foundation
import ApplicationServices

public enum TerminalSelectionState: Sendable, CaseIterable {
    case selected, empty, unknown
}

/// Selection metadata only, on the action worker. No text, clipboard, screen,
/// AX tree traversal, polling, or process-wide AX timeout changes.
enum TerminalSelectionReader {
    static func classify(_ ranges: [CFRange]) -> TerminalSelectionState {
        guard ranges.count <= 16, ranges.allSatisfy({
            $0.location >= 0 && $0.location != NSNotFound && $0.length >= 0 &&
            $0.location <= Int.max - $0.length
        }) else { return .unknown }
        return ranges.contains { $0.length > 0 } ? .selected : .empty
    }

    static func range(_ value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var result = CFRange()
        return AXValueGetValue(ax, .cfRange, &result) ? result : nil
    }

    static func read(pid: Int32) -> TerminalSelectionState {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.025)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String, [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) else { return .unknown }

        var count: CFIndex = 0
        let state: TerminalSelectionState
        if AXUIElementGetAttributeValueCount(element, kAXSelectedTextRangesAttribute as CFString, &count) == .success {
            guard (0...16).contains(count) else { return .unknown }
            if count == 0 { state = .empty }
            else {
                var values: CFArray?
                guard AXUIElementCopyAttributeValues(element, kAXSelectedTextRangesAttribute as CFString, 0, count, &values) == .success,
                      let values, CFArrayGetCount(values) == count else { return .unknown }
                var ranges: [CFRange] = []
                for index in 0..<count {
                    let value = unsafeBitCast(CFArrayGetValueAtIndex(values, index), to: CFTypeRef.self)
                    guard let range = range(value) else { return .unknown }
                    ranges.append(range)
                }
                state = classify(ranges)
            }
        } else {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
                  let value, let range = range(value) else { return .unknown }
            state = classify([range])
        }
        // A focus change inside the same App also invalidates this observation.
        var current: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &current) == .success,
              let current, CFEqual(focused, current) else { return .unknown }
        return state
    }
}
