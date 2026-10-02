public enum HIDElementRole: Sendable, Equatable {
    case key, button, x, y, wheel, pan, padding, unsupported
    public var pointing: Bool { switch self { case .button, .x, .y, .wheel, .pan: true; default: false } }
}
public struct HIDElementDescriptor: Sendable {
    public let page: UInt32, usage: UInt32
    public let minimum: Int, maximum: Int
    public let relative: Bool
    public init(page: UInt32, usage: UInt32, minimum: Int, maximum: Int, relative: Bool) {
        self.page = page; self.usage = usage; self.minimum = minimum; self.maximum = maximum; self.relative = relative
    }
    public var role: HIDElementRole {
        guard minimum <= maximum else { return .unsupported }
        if usage == 0 && minimum == 0 && maximum == 0 { return .padding }
        if relative && minimum >= -1023 && maximum <= 1023 {
            if page == 1 { switch usage { case 0x30: return .x; case 0x31: return .y; case 0x38: return .wheel; default: break } }
            if page == 12 && usage == 0x238 { return .pan }
        }
        guard !relative && minimum == 0 && maximum > 0 && maximum <= 65535 && usage <= UInt16.max else { return .unsupported }
        if page == 7 && (4...0xe7).contains(usage) { return .key }
        guard maximum == 1 else { return .unsupported }
        if page == 9 && (1...32).contains(usage) { return .button }
        if [UInt32(12), 0xff, 0xff01].contains(page) && usage > 0 { return .key }
        if page == 1 && (0x81...0x83).contains(usage) { return .key }
        return .unsupported
    }
}
public enum HIDDescriptorPolicy {
    public static func accepts(_ elements: [HIDElementDescriptor]) -> Bool {
        !elements.isEmpty && elements.count <= 2048 && elements.contains { $0.role == .key } &&
            elements.allSatisfy { $0.role != .unsupported }
    }
}
/// Shared pointing output keeps each captured device's button contribution separate.
public struct HIDPointingLedger: Sendable {
    private var devices = [UInt64?](repeating: nil, count: 16)
    private var held = [UInt32](repeating: 0, count: 16)
    public init() {}
    public var buttons: UInt32 { held.reduce(0, |) }
    public mutating func register(_ id: UInt64) -> Bool {
        if devices.contains(id) { return true }
        guard let i = devices.firstIndex(of: nil) else { return false }; devices[i] = id; return true
    }
    public mutating func disconnect(_ id: UInt64) {
        guard let i = devices.firstIndex(of: id) else { return }; held[i] = 0; devices[i] = nil
    }
    public mutating func reset() { for i in held.indices { held[i] = 0 } }
    @discardableResult public mutating func observe(device: UInt64, role: HIDElementRole, usage: UInt32, value: Int) -> Bool {
        guard let i = devices.firstIndex(of: device) else { return false }
        if role == .button {
            guard (1...32).contains(usage), value == 0 || value == 1 else { return false }
            let bit = UInt32(1) << (usage - 1)
            if value == 0 { held[i] &= ~bit } else { held[i] |= bit }
            return true
        }
        return role.pointing && (-1023...1023).contains(value)
    }
}
