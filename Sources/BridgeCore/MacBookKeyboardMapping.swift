/// Metadata only: Universal Control and virtual keyboards are never mapping targets.
public struct MacBookKeyboardIdentity: Equatable, Sendable {
    public var registryID: UInt64
    public var builtIn: Bool
    public var vendorID: Int
    public var transport: String
    public var product: String
    public var virtual: Bool
    public init(registryID: UInt64, builtIn: Bool, vendorID: Int, transport: String,
                product: String, virtual: Bool = false) {
        self.registryID = registryID; self.builtIn = builtIn; self.vendorID = vendorID
        self.transport = transport; self.product = product; self.virtual = virtual
    }
    public func isLocalMacBookKeyboard(portable: Bool) -> Bool {
        let name = product.lowercased()
        return portable && builtIn && vendorID == 1452 && registryID != 0 && !virtual &&
            ["SPI", "ADB", "USB"].contains(transport.uppercased()) &&
            !name.hasPrefix("v-") && !name.contains("virtual") && !name.contains("karabiner") &&
            !name.contains("universal control")
    }
}

public struct NativeKeyMapping: Codable, Equatable, Sendable {
    public var source: UInt64
    public var destination: UInt64
    public init(_ source: UInt64, _ destination: UInt64) {
        self.source = source; self.destination = destination
    }
}

/// Apple's vendor Fn usages and USB left Control. No Command/Option/right Control changes.
public enum MacBookFnControlMapping {
    public static let fn: UInt64 = 0xff00000003
    public static let vendorFn: UInt64 = 0xff0100000003
    public static let leftControl: UInt64 = 0x7000000e0
    public static let swap = [NativeKeyMapping(fn, leftControl), NativeKeyMapping(vendorFn, leftControl),
                              NativeKeyMapping(leftControl, fn)]
    public static func owns(_ source: UInt64) -> Bool { swap.contains { $0.source == source } }
    public static func containsSwap(_ current: [NativeKeyMapping]) -> Bool {
        swap.allSatisfy { current.contains($0) } && current.filter { owns($0.source) }.count == swap.count
    }
    public static func hasUserConflict(_ current: [NativeKeyMapping]) -> Bool {
        current.contains { owns($0.source) && $0.source != $0.destination }
    }
    /// macOS applies modifier preferences before UserKeyMapping. Avoid composing a swap twice.
    public static func hasModifierConflict(_ current: [NativeKeyMapping]) -> Bool {
        current.contains { $0.source != $0.destination && (owns($0.source) || owns($0.destination)) }
    }
    public static func applying(to current: [NativeKeyMapping]) -> [NativeKeyMapping] {
        current.filter { !owns($0.source) } + swap
    }
    /// Restore only entries still owned by this app; retain concurrent changes by other software.
    public static func restoring(_ current: [NativeKeyMapping], original: [NativeKeyMapping]) -> [NativeKeyMapping] {
        var result = current
        for owned in swap where result.contains(owned) {
            // Another tool can add a different destination for the same source.
            // Remove only our exact pair; never replace its newer mapping with
            // the saved original while that tool still owns the source.
            result.removeAll { $0 == owned }
            if !result.contains(where: { $0.source == owned.source }) {
                result += original.filter { $0.source == owned.source }
            }
        }
        return result
    }
}
