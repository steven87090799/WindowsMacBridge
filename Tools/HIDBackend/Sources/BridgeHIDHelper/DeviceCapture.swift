import Foundation
import IOKit.hid
import Carbon
import ApplicationServices
import SystemConfiguration
import BridgeCore
import HIDProtocol
import HIDLifecycle
import VirtualHID

/// Everything mutable is owned by the main CFRunLoop, including device callbacks.
final class DeviceCapture {
    private final class Device {
        let hid: IOHIDDevice, id: UInt64, builtIn: Bool, elements: [IOHIDElement]
        let apple834: Bool
        var seized = false, observed = false
        init(_ hid: IOHIDDevice, id: UInt64, builtIn: Bool, apple834: Bool, elements: [IOHIDElement]) {
            self.hid = hid; self.id = id; self.builtIn = builtIn; self.apple834 = apple834; self.elements = elements
        }
    }
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var devices: [Device] = [] // Membership changes only on discovery, never during input processing.
    private var client: OpaquePointer?
    private var lifecycle = CaptureLifecycle()
    private var engine = HIDTranslationEngine()
    private var output = HIDOutput()
    private var report = WMBHIDState()
    private var config = HIDConfiguration()
    private var lastHeartbeat: Double = 0
    private var controllerUID: uid_t = 0
    private var currentRestart: UInt64 = 0
    private var failClosed = false
    private var fault = ""
    private var maxMicroseconds: Double = 0
    private var lastDiscovery: Double = 0
    private var timer: Timer?
    private var actions: [(ShortcutAction, Int32, UInt64)] = []
    var onAction: ((ShortcutAction, Int32, UInt64) -> Void)?
    var status = HIDStatus()
    init() {
        // Enumerate without opening all keyboards. Individual eligible services are opened below.
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DeviceCapture>.fromOpaque(context).takeUnretainedValue().added(device)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DeviceCapture>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if let all = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> { for device in all { added(device) } }
    }
    static func consoleUID() -> uid_t? {
        var uid: uid_t = 0, gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?, name != "loginwindow", uid != 0 else { return nil }
        return uid
    }
    func configure(_ next: HIDConfiguration, uid: uid_t) {
        controllerUID = uid; lastHeartbeat = ProcessInfo.processInfo.systemUptime
        if next.restartToken != currentRestart {
            currentRestart = next.restartToken; execute(lifecycle.restart()); engine.restart(); failClosed = false; fault = ""
        }
        if config.generation != next.generation {
            actions.removeAll(keepingCapacity: true); engine.invalidate()
            if devices.contains(where: { $0.seized }) { sendOutput() }
        }
        if config.keyboardScope != next.keyboardScope { stopCapture() }
        config = next
        if next.enabled && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            timer?.tolerance = 0.025
        } else if !next.enabled { timer?.invalidate(); timer = nil }
        if !next.diagnostics { status.lastRule = nil }
        engine.configure(context: next.context, layoutSupported: next.layoutSupported,
                         finderEnabled: next.finderEnabled,
                         finderPermanentDeleteEnabled: next.finderPermanentDeleteEnabled,
                         textNavigationEnabled: next.textNavigationEnabled,
                         altF4Enabled: next.altF4Enabled,
                         windowsKeyModifier: next.windowsKeyModifier,
                         macBookFnControlSwap: next.macBookFnControlSwap,
                         winRunEnabled: next.winRunEnabled,
                         winSettingsEnabled: next.winSettingsEnabled,
                         winTaskViewEnabled: next.winTaskViewEnabled,
                         finderBrightnessEnterEnabled: next.finderBrightnessEnterEnabled,
                         screenshotEnabled: next.screenshotEnabled, printScreenBehavior: next.printScreenBehavior)
        if !next.enabled || !next.sessionActive { stopCapture() }
        else if devices.contains(where: { $0.seized }) { sendOutput() }
        tick()
    }
    func stop() { config = HIDConfiguration(); timer?.invalidate(); timer = nil; lastHeartbeat = 0; stopCapture() }
    private func selected(_ device: Device) -> Bool {
        config.keyboardScope == .allKeyboards || device.builtIn || device.apple834
    }
    private func stopCapture() {
        actions.removeAll(keepingCapacity: true)
        execute(lifecycle.stop()); engine.invalidate()
        if let client { wmb_virtual_hid_destroy(client); self.client = nil }
    }
    private func added(_ hid: IOHIDDevice) {
        guard devices.count < 16, !devices.contains(where: { $0.hid == hid }) else { return }
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(hid, key as CFString) as? NSNumber)?.intValue ?? 0 }
        let product = IOHIDDeviceGetProperty(hid, kIOHIDProductKey as CFString) as? String ?? ""
        // Never seize any virtual keyboard or a composite pointing/multitouch service.
        guard !product.localizedCaseInsensitiveContains("virtual"), number(kIOHIDVendorIDKey) != 0x16c0,
              !product.hasPrefix("V-"), !product.localizedCaseInsensitiveContains("Universal Control"),
              number("VirtualHIDDevice") == 0,
              !IOHIDDeviceConformsTo(hid, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)),
              !IOHIDDeviceConformsTo(hid, 0x0d, 5) else { return }
        let builtIn = number(kIOHIDBuiltInKey) != 0
        let apple834 = number(kIOHIDVendorIDKey) == 1452 && number(kIOHIDProductIDKey) == 834
        guard let all = IOHIDDeviceCopyMatchingElements(hid, nil, 0) as? [IOHIDElement] else { return }
        let input = all.filter { (element: IOHIDElement) -> Bool in
            let t = IOHIDElementGetType(element).rawValue
            return (1...4).contains(t)
        }
        let keys = input.filter { Self.supported($0) }
        guard !keys.isEmpty,
              IOHIDDeviceConformsTo(hid, 1, 6) || keys.contains(where: { IOHIDElementGetUsagePage($0) == 0x0c || Self.isFn($0) }),
              input.allSatisfy({ Self.supported($0) || IOHIDElementGetUsage($0) == 0 }) else { return }
        var id: UInt64 = 0; _ = IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(hid), &id)
        guard id != 0, engine.register(id, builtIn: builtIn) else { return }
        let device = Device(hid, id: id, builtIn: builtIn, apple834: apple834, elements: keys); devices.append(device)
        IOHIDDeviceRegisterInputValueCallback(hid, { context, result, _, value in
            guard let context else { return }
            Unmanaged<DeviceCapture>.fromOpaque(context).takeUnretainedValue().received(result, value: value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if selected(device) && lifecycle.phase == .capturing { execute(lifecycle.stop()); engine.invalidate() }
    }
    private static func isFn(_ e: IOHIDElement) -> Bool {
        HIDTranslationEngine.modifier(page: IOHIDElementGetUsagePage(e), usage: UInt16(truncatingIfNeeded: IOHIDElementGetUsage(e))) == .fn
    }
    private static func supported(_ e: IOHIDElement) -> Bool {
        let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e)
        // Boolean keys only. Unknown axes/collections never become keyboard input.
        guard IOHIDElementGetLogicalMin(e) == 0, IOHIDElementGetLogicalMax(e) == 1, usage <= UInt16.max else { return false }
        switch page {
        case 7: return usage >= 4 && usage <= 0xe7
        case 0x0c, 0xff, 0xff01: return usage > 0
        case 1: return (0x81...0x83).contains(usage) // power/sleep/wake only
        default: return false
        }
    }
    private func removed(_ hid: IOHIDDevice) {
        guard let i = devices.firstIndex(where: { $0.hid == hid }) else { return }
        let device = devices.remove(at: i); engine.disconnect(device.id)
        if device.seized || device.observed { IOHIDDeviceClose(hid, 0) }
        IOHIDDeviceUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if devices.contains(where: { $0.seized }) { sendOutput() }
        execute(lifecycle.stop())
    }
    private func neutral(_ device: Device) -> Bool {
        for e in device.elements {
            guard wmb_hid_element_is_neutral(device.hid, e) else { return false }
        }
        return true
    }
    private func execute(_ commands: [CaptureCommand]) {
        for command in commands {
            switch command {
            case .releaseVirtualOutputs:
                if let client { wmb_virtual_hid_reset(client) }
                engine.invalidate()
            case .closePhysicalDevices:
                for device in devices where device.seized || device.observed {
                    IOHIDDeviceClose(device.hid, device.seized ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0)
                    device.seized = false; device.observed = false
                    engine.disconnect(device.id); _ = engine.register(device.id, builtIn: device.builtIn)
                }
            case .openPhysicalDevices:
                var success = devices.contains(where: { selected($0) })
                for device in devices where selected(device) {
                    if device.observed { IOHIDDeviceClose(device.hid, 0); device.observed = false }
                    guard IOHIDDeviceOpen(device.hid, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else { success = false; break }
                    device.seized = true
                    // Recheck after the open: a key pressed in the observation/open gap aborts capture.
                    if !neutral(device) { success = false; break }
                }
                execute(lifecycle.captureCompleted(success: success))
                if !success { fault = "裝置擷取失敗；已釋放，請放開所有按鍵後重啟引擎。" }
            }
        }
    }
    private func sessionActive() -> Bool {
        guard Self.consoleUID() == controllerUID,
              let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dictionary[kCGSessionOnConsoleKey as String] as? Bool) == true &&
            (dictionary[kCGSessionLoginDoneKey as String] as? Bool) == true
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if config.enabled && now - lastDiscovery >= 30 {
            lastDiscovery = now
            if let present = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                for d in devices where !present.contains(d.hid) { removed(d.hid) }
                for d in present { added(d) }
            }
        }
        status.secureInput = IsSecureEventInputEnabled()
        status.permissions = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        // Native hand-back for clients that may own/read physical HID devices themselves.
        // Keep terminal/IDE identity reports, but never seize a Remote/VM/Game/Disabled device.
        let nativePass = HIDCapturePolicy.requiresNativePassThrough(mode: config.mode, layoutSupported: config.layoutSupported)
        let valid = config.enabled && config.sessionActive && sessionActive() && !status.secureInput && status.permissions &&
            now - lastHeartbeat < 1 && !failClosed && !engine.emergencyPaused && !nativePass
        if valid && client == nil { client = wmb_virtual_hid_create() }
        let driver = client.map { wmb_virtual_hid_status($0) } ?? 0
        status.driverReady = driver & UInt32(WMB_KEYBOARD_READY) != 0 && driver & UInt32(WMB_CONNECTION_FAULT | WMB_DRIVER_MISMATCH) == 0
        // Observation begins only after explicit enabled policy and permission. Never opens unrelated devices.
        if valid && status.driverReady && lifecycle.phase != .faulted {
            for device in devices where selected(device) && !device.observed && !device.seized {
                device.observed = IOHIDDeviceOpen(device.hid, 0) == kIOReturnSuccess
            }
        }
        var p = CapturePrerequisites()
        p.enabled = valid; p.sessionActive = sessionActive(); p.secureInput = status.secureInput
        p.permissions = status.permissions; p.authenticatedController = controllerUID != 0
        p.driverReady = status.driverReady; p.lastHeartbeat = lastHeartbeat
        let targets = devices.filter { selected($0) }
        p.keysNeutral = lifecycle.phase == .capturing || (!targets.isEmpty && targets.allSatisfy { ($0.observed || $0.seized) && neutral($0) })
        execute(lifecycle.update(p, now: now))
        if !valid || !status.driverReady || lifecycle.phase == .faulted {
            for d in devices where d.observed { IOHIDDeviceClose(d.hid, 0); d.observed = false }
        }
        if !valid {
            for d in devices where d.observed { IOHIDDeviceClose(d.hid, 0); d.observed = false }
            if let client { wmb_virtual_hid_destroy(client); self.client = nil }
        }
        // Allow-listed actions leave the device callback via a small queue.
        let pending = actions; actions.removeAll(keepingCapacity: true)
        if valid && lifecycle.phase == .capturing && !engine.manualPassThrough { for (action, pid, generation) in pending { onAction?(action, pid, generation) } }
        status.capturedDevices = devices.filter { $0.seized }.count; status.eligibleDevices = targets.count
        status.manualPassThrough = engine.manualPassThrough; status.emergencyPaused = engine.emergencyPaused
        status.processed = engine.processed; status.translated = engine.translated; status.maxMicroseconds = maxMicroseconds
        if !fault.isEmpty { status.state = fault }
        else if nativePass && config.enabled { status.state = "原生穿透：\(config.mode.title)；已釋放實體鍵盤" }
        else if !status.permissions { status.state = "等待 helper 輸入監控權限" }
        else if status.secureInput { status.state = "Secure Input：已釋放裝置" }
        else if !valid { status.state = "已停止擷取" }
        else if !status.driverReady { status.state = "等待 VirtualHID Driver；不擷取鍵盤" }
        else if devices.isEmpty { status.state = "找不到支援的目標鍵盤服務" }
        else { status.state = String(describing: lifecycle.phase) }
    }
    private func received(_ result: IOReturn, value: IOHIDValue) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { maxMicroseconds = max(maxMicroseconds, Double(DispatchTime.now().uptimeNanoseconds - started) / 1000) }
        let element = IOHIDValueGetElement(value), hid = IOHIDElementGetDevice(IOHIDValueGetElement(value))
        guard let device = devices.first(where: { $0.hid == hid }), device.seized else { return }
        guard result == kIOReturnSuccess, Self.supported(element), IOHIDValueGetLength(value) <= 8,
              !IsSecureEventInputEnabled(), ProcessInfo.processInfo.systemUptime - lastHeartbeat < 1 else {
            failClosed = true; fault = "輸入狀態失效；擷取已停止。"; execute(lifecycle.stop()); return
        }
        let wasPassing = engine.manualPassThrough
        let action = engine.observe(device: device.id, page: IOHIDElementGetUsagePage(element),
            usage: UInt16(IOHIDElementGetUsage(element)), down: IOHIDValueGetIntegerValue(value) != 0)
        if wasPassing != engine.manualPassThrough || engine.emergencyPaused { actions.removeAll(keepingCapacity: true) }
        if config.diagnostics, let rule = engine.lastRuleID { status.lastRule = rule }
        if let action {
            if actions.count < 16 { actions.append((action, config.processID, config.generation)) }
            else { failClosed = true; fault = "動作佇列已滿；擷取已停止。"; execute(lifecycle.stop()); return }
        }
        sendOutput()
    }
    private func sendOutput() {
        guard let client else { return }
        guard engine.render(into: &output) else { failClosed = true; fault = "輸出容量超限；擷取已停止。"; execute(lifecycle.stop()); return }
        report.modifiers = output.modifiers; report.fn = output.fn
        report.key_count = UInt8(output.keyCount); report.consumer_count = UInt8(output.consumerCount)
        report.top_case_count = UInt8(output.topCaseCount); report.vendor_count = UInt8(output.vendorCount); report.desktop_count = UInt8(output.desktopCount)
        withUnsafeMutableBytes(of: &report.keys) { bytes in output.keys.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.consumer_keys) { bytes in output.consumer.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.top_case_keys) { bytes in output.topCase.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.vendor_keys) { bytes in output.vendor.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.desktop_keys) { bytes in output.desktop.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        if !wmb_virtual_hid_post(client, &report) { failClosed = true; fault = "VirtualHID 輸出中斷；已釋放鍵盤。"; execute(lifecycle.stop()) }
    }
}
