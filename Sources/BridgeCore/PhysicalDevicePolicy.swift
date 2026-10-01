import Foundation
import CryptoKit

public enum PhysicalDevicePolicy {
    public static func identity(vendor: Int, product: Int, location: Int, transport: String, builtIn: Bool, serial: String = "") -> String {
        // IORegistry entry IDs are session-local. Persist only a digest of bounded hardware
        // metadata; identical devices without serial numbers remain port/location-bound.
        let serialValue = String(decoding: serial.utf8.prefix(128), as: UTF8.self)
        let transportValue = String(decoding: transport.utf8.prefix(64), as: UTF8.self)
        let value = "\(vendor)|\(product)|\(serialValue.isEmpty ? location : 0)|\(transportValue)|\(builtIn)|\(serialValue)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func isVirtual(product: String, vendor: Int, virtualProperty: Bool, transport: String) -> Bool {
        virtualProperty || vendor == 0x16c0 || product.localizedCaseInsensitiveContains("virtual") ||
        product.hasPrefix("V-") || product.localizedCaseInsensitiveContains("Universal Control") ||
        transport.localizedCaseInsensitiveContains("virtual")
    }
    public static func selected(identity: String, scope: KeyboardScope, builtIn: Bool, apple834: Bool,
                                preferences: [DeviceInputPreference]) -> Bool {
        guard preferences.prefix(16).first(where: { $0.identity == identity })?.experience != .nativeMac else { return false }
        return scope == .allKeyboards || builtIn || apple834
    }
}
