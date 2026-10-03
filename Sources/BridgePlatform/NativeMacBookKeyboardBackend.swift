import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import BridgeCore
import ApplicationServices

/// Apple TN2450 service properties. The client cannot receive a keyboard event stream.
@MainActor public final class NativeMacBookKeyboardBackend: MacBookKeyboardMappingBackend {
    public let portable: Bool
    public let bootID: String
    public var keysNeutral: Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        guard flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty else { return false }
        return !(UInt16(0)..<128).contains { $0 != 57 && CGEventSource.keyState(.hidSystemState, key: $0) }
    }
    private let client: IOHIDEventSystemClient
    private var handles: [UInt64: IOHIDServiceClient] = [:]
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var change: (@MainActor () -> Void)?
    private var queued = false
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"
    public init() {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if battery != 0 {
            portable = (IORegistryEntryCreateCFProperty(battery, "BatteryInstalled" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.boolValue == true
            IOObjectRelease(battery)
        } else { portable = false }
        var size = 0
        if sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0 && (1...128).contains(size) {
            var bytes = [CChar](repeating: 0, count: size)
            bootID = sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 ?
                String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        } else { bootID = "" }
    }
    /// Apple Silicon portables publish well over 100 non-keyboard event services
    /// (sensors, buttons, lid). Bound the scan and the keyboard rows separately;
    /// counting every service against the keyboard bound disabled the swap there.
    static let serviceScanLimit = 4096
    static let keyboardServiceLimit = 128
    public func services() -> [MacBookKeyboardService]? {
        handles.removeAll(keepingCapacity: true)
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient],
              all.count <= Self.serviceScanLimit else { return nil }
        let keyboards = all.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
        }
        guard keyboards.count <= Self.keyboardServiceLimit else { return nil }
        return keyboards.compactMap { service in
            guard let id = IOHIDServiceClientGetRegistryID(service) as? NSNumber else { return nil }
            func property(_ key: String) -> Any? { IOHIDServiceClientCopyProperty(service, key as CFString) }
            handles[id.uint64Value] = service
            let identity = MacBookKeyboardIdentity(registryID: id.uint64Value,
                builtIn: (property(kIOHIDBuiltInKey) as? NSNumber)?.boolValue == true,
                vendorID: (property(kIOHIDVendorIDKey) as? NSNumber)?.intValue ?? 0,
                transport: property(kIOHIDTransportKey) as? String ?? "",
                product: property(kIOHIDProductKey) as? String ?? "",
                virtual: (property("VirtualHIDDevice") as? NSNumber)?.boolValue == true)
            return MacBookKeyboardService(identity: identity,
                userMapping: Self.decode(property(kIOHIDUserKeyUsageMapKey)),
                modifierMapping: Self.decode(property(kIOHIDKeyboardModifierMappingPairsKey)))
        }
    }
    // TN2450 specifies UserKeyMapping with HIDKeyboardModifierMappingSrc/Dst.
    // The system ModifierMappingPairs table is read only for conflict detection.
    public func write(_ mapping: [NativeKeyMapping], serviceID: UInt64) -> Bool {
        guard let service = handles[serviceID],
              services()?.contains(where: { $0.identity.registryID == serviceID &&
                  $0.identity.isLocalMacBookKeyboard(portable: portable) }) == true else { return false }
        let value = mapping.map { [Self.sourceKey: NSNumber(value: $0.source),
                                  Self.destinationKey: NSNumber(value: $0.destination)] }
        return IOHIDServiceClientSetProperty(service, kIOHIDUserKeyUsageMapKey as CFString, value as CFArray)
    }
    static func decode(_ value: Any?) -> [NativeKeyMapping]? {
        guard let value else { return [] }
        guard let pairs = value as? [[String: Any]], pairs.count <= 256 else { return nil }
        var result: [NativeKeyMapping] = []
        for pair in pairs {
            guard Set(pair.keys) == [sourceKey, destinationKey],
                  let source = pair[sourceKey] as? NSNumber, let destination = pair[destinationKey] as? NSNumber,
                  CFGetTypeID(source) != CFBooleanGetTypeID(), CFGetTypeID(destination) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: source.objCType)),
                  !["f", "d"].contains(String(cString: destination.objCType)),
                  source.int64Value >= 0, destination.int64Value >= 0,
                  !result.contains(where: { $0.source == source.uint64Value }) else { return nil }
            result.append(NativeKeyMapping(source.uint64Value, destination.uint64Value))
        }
        return result
    }
    public func observeChanges(_ action: @escaping @MainActor () -> Void) -> Bool {
        stopObserving()
        guard let created = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        port = created; change = action
        IONotificationPortSetDispatchQueue(created, .main)
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            // Kernel built-in services only; never Universal Control's virtual services.
            guard let matching = IOServiceMatching("IOHIDEventService") else { stopObserving(); return false }
            let properties = [kIOHIDBuiltInKey: true] as CFDictionary
            let propertyKey = kIOPropertyMatchKey as CFString
            // Unmanaged does not retain its argument. The optimizer may release a
            // temporary bridged NSString before CFDictionarySetValue reads its hash.
            withExtendedLifetime((propertyKey, properties)) {
                CFDictionarySetValue(matching, Unmanaged.passUnretained(propertyKey).toOpaque(),
                                     Unmanaged.passUnretained(properties).toOpaque())
            }
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(created, notification, matching, { pointer, iterator in
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                guard let pointer else { return }
                MainActor.assumeIsolated {
                    Unmanaged<NativeMacBookKeyboardBackend>.fromOpaque(pointer).takeUnretainedValue().scheduleChange()
                }
            }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
            guard result == KERN_SUCCESS else { stopObserving(); return false }
            iterators.append(iterator)
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
        }
        return true
    }
    private func scheduleChange() {
        guard !queued else { return }
        queued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            queued = false; change?()
        }
    }
    public func stopObserving() {
        change = nil
        if let port { IONotificationPortSetDispatchQueue(port, nil); IONotificationPortDestroy(port) }
        port = nil
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
    }
    public func diagnosticReport() -> String {
        guard let all = services() else { return "Native Fn/Control: keyboard service inventory unavailable; no mapping started." }
        let candidates = all.filter { $0.identity.isLocalMacBookKeyboard(portable: portable) }
        return "Native Fn/Control: portable=\(portable), local physical candidates=\(candidates.count), keyboard services=\(all.count).\n" +
            "Virtual/Universal Control/external services are excluded; no mapping or input capture started."
    }
}
