import Foundation
import IOKit.hid
import BridgeCore

/// Discovery only. Does not open, seize, schedule or register input callbacks.
public enum HIDDeviceInventory {
    public static func keyboards() -> [KeyboardDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                       kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return devices.map { device in
            func integer(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
            var identifier: UInt64 = 0
            let service = IOHIDDeviceGetService(device)
            if service != 0 { _ = IORegistryEntryGetRegistryEntryID(service, &identifier) }
            return KeyboardDevice(registryID: identifier, builtIn: integer(kIOHIDBuiltInKey) != 0,
                                  vendorID: integer(kIOHIDVendorIDKey), productID: integer(kIOHIDProductIDKey))
        }.sorted { $0.registryID < $1.registryID }
    }
    public static func report() -> String {
        let devices = keyboards()
        var rows = ["Available backends: CGEventTap preview / Device HID helper",
                    "Complete Karabiner replacement: physical acceptance pending",
                    "Device HID installation/readiness: inspect App settings; inventory does not start the helper",
                    "IOHID inventory (metadata only): \(devices.count) keyboard services"]
        rows += devices.map { "id=\($0.registryID) builtIn=\($0.builtIn) VID=\($0.vendorID) PID=\($0.productID) target=\($0.matchesRequestedScope)" }
        rows.append("Inventory is not proof of capture or event-to-device correlation. No keyboard was seized.")
        return rows.joined(separator: "\n")
    }
}
