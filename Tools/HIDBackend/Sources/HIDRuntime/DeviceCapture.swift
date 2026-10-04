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
private final class CaptureStatusRelay: @unchecked Sendable {
    weak var owner: DeviceCapture?
    private let pending = DeferredSignalMailbox()
    func signal() {
        guard pending.offer(1) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, pending.take() != 0 else { return }
            owner?.driverChanged()
        }
    }
}
final class DeviceCapture {
    private final class Device {
        let hid: IOHIDDevice, id: UInt64, builtIn: Bool, elements: [IOHIDElement]
        let apple834: Bool
        let identity: String, product: String
        let roles: [UInt32: HIDElementRole], neutralElements: [IOHIDElement]
        let hasPointing: Bool
        var seized = false, observed = false
        init(_ hid: IOHIDDevice, id: UInt64, builtIn: Bool, apple834: Bool, elements: [IOHIDElement], identity: String, product: String) {
            self.hid = hid; self.id = id; self.builtIn = builtIn; self.apple834 = apple834; self.elements = elements
            self.identity = identity; self.product = String(decoding: product.utf8.prefix(240), as: UTF8.self)
            // A malformed descriptor can repeat a cookie; never trap the root process on it.
            self.roles = Dictionary(elements.map { (IOHIDElementGetCookie($0), DeviceCapture.descriptor($0).role) },
                                    uniquingKeysWith: { first, _ in first })
            self.neutralElements = elements.filter { let role = DeviceCapture.descriptor($0).role; return role == .key || role == .button }
            self.hasPointing = roles.values.contains { $0.pointing }
        }
    }
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var devices: [Device] = [] // Membership changes only on discovery, never during input processing.
    private var client: OpaquePointer?
    private var lifecycle = CaptureLifecycle()
    private var engine = HIDTranslationEngine()
    private var output = HIDOutput()
    private var pointing = HIDPointingLedger()
    private var pendingPointing = WMBPointingState()
    private var pointingTimestamp: UInt64 = 0
    private var pointingFields: UInt8 = 0
    private var pointingFlushQueued = false
    private var report = WMBHIDState()
    private var config = HIDConfiguration()
    private var controllerUID: uid_t = 0
    /// Console ownership for the authenticated controller, refreshed per tick and
    /// on console-user changes; device callbacks never query configd themselves.
    private var consoleSessionValid = false
    private var consoleStore: SCDynamicStore?
    private var tickQueued = false
    /// Consecutive observe-to-seize neutral races; bounded so a flapping element
    /// becomes an explicit fault instead of a busy retry loop.
    private var neutralAborts = 0
    private static let neutralAbortLimit = 3
    private var currentRestart: UInt64 = 0
    private var failClosed = false
    private var fault = ""
    private var maxMicroseconds: Double = 0
    private let heldSafety = HeldSafetyTimer()
    private let relay = CaptureStatusRelay()
    private static let teardownQueue = DispatchQueue(label: "WindowsMacBridge.virtual-hid-teardown", qos: .utility)
    private var tearingDown = false
    private var teardownReplies: [() -> Void] = []
    var onStatus: ((HIDStatus, UInt64) -> Void)?
    private var publishedStatus = HIDStatus()
    func driverChanged() { tick() }
    private var actions: [(ShortcutAction, Int32, UInt64)] = []
    var onAction: ((ShortcutAction, Int32, UInt64) -> Void)?
    var status = HIDStatus()
    init() {
        relay.owner = self
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
        // Fast user switching or logout releases capture without waiting for the
        // old session's App, which may no longer be scheduled.
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(relay).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        if let store = SCDynamicStoreCreate(nil, "WindowsMacBridge.HIDConsole" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<CaptureStatusRelay>.fromOpaque(info).takeUnretainedValue().signal()
        }, &context) {
            let keys = [SCDynamicStoreKeyCreateConsoleUser(nil)] as CFArray
            if SCDynamicStoreSetNotificationKeys(store, keys, nil), SCDynamicStoreSetDispatchQueue(store, .main) {
                consoleStore = store
            }
        }
    }
    static func consoleUID() -> uid_t? {
        var uid: uid_t = 0, gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?, name != "loginwindow", uid != 0 else { return nil }
        return uid
    }
    func configure(_ next: HIDConfiguration, uid: uid_t) {
        controllerUID = uid
        if next.restartToken != currentRestart {
            currentRestart = next.restartToken; execute(lifecycle.restart()); engine.restart(); failClosed = false; fault = ""
            neutralAborts = 0
        }
        if !config.sameCapturePolicy(as: next) {
            pendingPointing = .init(); pointingFields = 0
            actions.removeAll(keepingCapacity: true); engine.invalidate()
            if devices.contains(where: { $0.seized }) { sendOutput() }
        }
        if config.keyboardScope != next.keyboardScope { stopCapture() }
        if config.actionGeneration != next.actionGeneration { actions.removeAll(keepingCapacity: true) }
        if config.deviceInputs != next.deviceInputs {
            actions.removeAll(keepingCapacity: true)
            for d in devices where !PhysicalDevicePolicy.selected(identity: d.identity, scope: next.keyboardScope,
                builtIn: d.builtIn, apple834: d.apple834, preferences: next.deviceInputs) && (d.seized || d.observed) {
                // Release this device's contribution before returning its physical service.
                if d.seized && d.hasPointing { flushPointing() }
                engine.disconnect(d.id); _ = engine.register(d.id, builtIn: d.builtIn)
                pointing.disconnect(d.id); _ = pointing.register(d.id)
                if d.seized { sendOutput() }
                if d.seized && d.hasPointing { flushPointing(force: true) }
                IOHIDDeviceClose(d.hid, d.seized ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0)
                d.seized = false; d.observed = false
            }
        }
        config = next
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
                         screenshotEnabled: next.screenshotEnabled, printScreenBehavior: next.printScreenBehavior,
                         transportOnly: next.transportOnly, actionsEnabled: false)
        if !next.enabled || !next.sessionActive { stopCapture() }
        else if devices.contains(where: { $0.seized }) { sendOutput() }
        tick()
    }
    func stop(completion: (() -> Void)? = nil) {
        config = HIDConfiguration(); heldSafety.cancel(); consoleSessionValid = false
        if let completion { teardownReplies.append(completion) }
        stopCapture()
        if !tearingDown { finishTeardown() }
    }
    private func finishTeardown() {
        let replies = teardownReplies; teardownReplies.removeAll()
        for reply in replies { reply() }
    }
    private func destroyVirtualClient() {
        guard let old = client else { return }
        client = nil; tearingDown = true
        wmb_virtual_hid_set_status_callback(old, nil, nil)
        let keepRelayAlive = relay
        Self.teardownQueue.async { [weak self] in
            withExtendedLifetime(keepRelayAlive) { wmb_virtual_hid_destroy(old) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                tearingDown = false; finishTeardown()
                if config.enabled { tick() }
            }
        }
    }
    private func selected(_ device: Device) -> Bool {
        PhysicalDevicePolicy.selected(identity: device.identity, scope: config.keyboardScope, builtIn: device.builtIn,
                                      apple834: device.apple834, preferences: config.deviceInputs)
    }
    private func stopCapture() {
        actions.removeAll(keepingCapacity: true)
        execute(lifecycle.stop()); engine.invalidate(); report = .init()
        destroyVirtualClient()
    }
    private func added(_ hid: IOHIDDevice) {
        guard devices.count < 16, !devices.contains(where: { $0.hid == hid }) else { return }
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(hid, key as CFString) as? NSNumber)?.intValue ?? 0 }
        let product = IOHIDDeviceGetProperty(hid, kIOHIDProductKey as CFString) as? String ?? ""
        let transport = IOHIDDeviceGetProperty(hid, kIOHIDTransportKey as CFString) as? String ?? ""
        // A mixed service is seized only if every input field can be forwarded.
        guard !PhysicalDevicePolicy.isVirtual(product: product, vendor: number(kIOHIDVendorIDKey),
              virtualProperty: number("VirtualHIDDevice") != 0, transport: transport),
              !IOHIDDeviceConformsTo(hid, 0x0d, 5) else { return }
        let builtIn = number(kIOHIDBuiltInKey) != 0
        let apple834 = number(kIOHIDVendorIDKey) == 1452 && number(kIOHIDProductIDKey) == 834
        guard let all = IOHIDDeviceCopyMatchingElements(hid, nil, 0) as? [IOHIDElement], all.count <= 2048 else { return }
        let input = all.filter { (element: IOHIDElement) -> Bool in
            let t = IOHIDElementGetType(element).rawValue
            return (1...4).contains(t)
        }
        guard HIDDescriptorPolicy.accepts(input.map(Self.descriptor)) else { return }
        let elements = input.filter { Self.descriptor($0).role != .padding }
        guard !elements.contains(where: { Self.descriptor($0).role.pointing }) ||
              elements.contains(where: { IOHIDElementGetUsagePage($0) == 7 }) else { return }
        var id: UInt64 = 0; _ = IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(hid), &id)
        guard id != 0, engine.register(id, builtIn: builtIn) else { return }
        guard pointing.register(id) else { engine.disconnect(id); return }
        let identity = PhysicalDevicePolicy.identity(vendor: number(kIOHIDVendorIDKey), product: number(kIOHIDProductIDKey),
            location: number(kIOHIDLocationIDKey), transport: transport, builtIn: builtIn,
            serial: IOHIDDeviceGetProperty(hid, kIOHIDSerialNumberKey as CFString) as? String ?? "")
        let device = Device(hid, id: id, builtIn: builtIn, apple834: apple834, elements: elements, identity: identity, product: product); devices.append(device)
        IOHIDDeviceRegisterInputValueCallback(hid, { context, result, _, value in
            guard let context else { return }
            Unmanaged<DeviceCapture>.fromOpaque(context).takeUnretainedValue().received(result, value: value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if config.enabled { scheduleTick() }
    }
    private static func descriptor(_ e: IOHIDElement) -> HIDElementDescriptor {
        .init(page: IOHIDElementGetUsagePage(e), usage: IOHIDElementGetUsage(e),
              minimum: IOHIDElementGetLogicalMin(e), maximum: IOHIDElementGetLogicalMax(e), relative: IOHIDElementIsRelative(e))
    }
    private func captureReady(_ device: Device) -> Bool {
        !device.hasPointing || client.map { wmb_virtual_hid_status($0) & UInt32(WMB_POINTING_READY) != 0 } == true
    }
    private func removed(_ hid: IOHIDDevice) {
        guard let i = devices.firstIndex(where: { $0.hid == hid }) else { return }
        let device = devices[i]
        if device.hasPointing { flushPointing() }
        devices.remove(at: i); engine.disconnect(device.id)
        pointing.disconnect(device.id)
        if device.seized || device.observed { IOHIDDeviceClose(hid, device.seized ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0) }
        IOHIDDeviceUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if devices.contains(where: { $0.seized }) { sendOutput() }
        if device.hasPointing { flushPointing(force: true) }
        execute(lifecycle.deviceRemoved(remainingCaptured: devices.contains(where: { $0.seized })))
        tick()
    }
    private func neutral(_ device: Device) -> Bool {
        for e in device.neutralElements {
            guard wmb_hid_element_is_neutral(device.hid, e) else { return false }
        }
        return true
    }
    private func execute(_ commands: [CaptureCommand]) {
        for command in commands {
            switch command {
            case .releaseVirtualOutputs:
                pointing.reset(); pendingPointing = .init(); pointingFields = 0
                if let client { wmb_virtual_hid_reset(client) }
                engine.invalidate()
            case .closePhysicalDevices:
                for device in devices where device.seized || device.observed {
                    IOHIDDeviceClose(device.hid, device.seized ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0)
                    device.seized = false; device.observed = false
                    engine.disconnect(device.id); _ = engine.register(device.id, builtIn: device.builtIn)
                    pointing.disconnect(device.id); _ = pointing.register(device.id)
                }
            case .openPhysicalDevices:
                var opened = devices.contains(where: { selected($0) && captureReady($0) })
                var neutralAfterSeize = true
                for device in devices where selected(device) && captureReady(device) {
                    if device.observed { IOHIDDeviceClose(device.hid, 0); device.observed = false }
                    guard IOHIDDeviceOpen(device.hid, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else { opened = false; break }
                    device.seized = true
                    // Recheck after the open: a key pressed in the observation/open gap aborts capture.
                    if !neutral(device) { neutralAfterSeize = false; break }
                }
                if opened && !neutralAfterSeize && neutralAborts < Self.neutralAbortLimit {
                    // A held key is not a device fault: release and wait for neutral again.
                    neutralAborts += 1
                    execute(lifecycle.captureAborted()); scheduleTick()
                } else {
                    let success = opened && neutralAfterSeize
                    execute(lifecycle.captureCompleted(success: success))
                    if success { neutralAborts = 0 }
                    else { fault = "裝置擷取失敗；已釋放，請放開所有按鍵後重啟引擎。" }
                }
            }
        }
    }
    /// A system LaunchDaemon is outside every Quartz GUI session, where
    /// CGSessionCopyCurrentDictionary returns NULL by contract. Session state comes
    /// from the authenticated App; the daemon independently requires that App's
    /// user to own the console (configd, also notified on console-user change).
    private func refreshConsoleSession() -> Bool {
        consoleSessionValid = controllerUID != 0 && Self.consoleUID() == controllerUID && config.sessionActive
        return consoleSessionValid
    }
    private func scheduleTick() {
        guard !tickQueued else { return }
        tickQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            tickQueued = false; tick()
        }
    }
    /// Device, report or output-path errors need an explicit engine restart.
    /// The follow-up tick publishes the fault and retires the virtual client.
    private func failClose(_ message: String) {
        failClosed = true; fault = message
        execute(lifecycle.stop()); scheduleTick()
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let session = refreshConsoleSession()
        status.secureInput = IsSecureEventInputEnabled()
        status.permissions = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        // Native hand-back for clients that may own/read physical HID devices themselves.
        // Keep terminal/IDE identity reports, but never seize a Remote/VM/Game/Disabled device.
        let nativePass = HIDCapturePolicy.requiresNativePassThrough(mode: config.mode, layoutSupported: config.layoutSupported, transportOnly: config.transportOnly)
        let valid = config.enabled && session && !status.secureInput && status.permissions &&
            !failClosed && !engine.emergencyPaused && !nativePass
        if valid && client == nil && !tearingDown {
            client = wmb_virtual_hid_create()
            if let client {
                wmb_virtual_hid_set_status_callback(client, { context in
                    guard let context else { return }
                    Unmanaged<CaptureStatusRelay>.fromOpaque(context).takeUnretainedValue().signal()
                }, Unmanaged.passUnretained(relay).toOpaque())
            }
        }
        if valid, let client, devices.contains(where: { selected($0) && $0.hasPointing }) { wmb_virtual_hid_enable_pointing(client) }
        let driver = client.map { wmb_virtual_hid_status($0) } ?? 0
        status.driverReady = driver & UInt32(WMB_KEYBOARD_READY) != 0 && driver & UInt32(WMB_CONNECTION_FAULT | WMB_DRIVER_MISMATCH) == 0
        // Pointing readiness was checked only at seize time. If it is lost later,
        // hand every device back; ready ones are recaptured below after neutral.
        if lifecycle.phase == .capturing && devices.contains(where: { $0.seized && !captureReady($0) }) {
            execute(lifecycle.stop())
        }
        // Observation begins only after explicit enabled policy and permission. Never opens unrelated devices.
        if valid && status.driverReady && lifecycle.phase != .faulted {
            for device in devices where selected(device) && captureReady(device) && !device.observed && !device.seized {
                device.observed = IOHIDDeviceOpen(device.hid, 0) == kIOReturnSuccess
            }
            // A new/reenabled keyboard waits for its own neutral state. Do not stop another
            // keyboard's active Ctrl chord merely because this device's preference changed.
            if lifecycle.phase == .capturing {
                for d in devices where selected(d) && captureReady(d) && d.observed && !d.seized && neutral(d) {
                    IOHIDDeviceClose(d.hid, 0); d.observed = false
                    if IOHIDDeviceOpen(d.hid, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess {
                        d.seized = true
                        if !neutral(d) {
                            IOHIDDeviceClose(d.hid, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)); d.seized = false
                        }
                    }
                }
            }
        }
        var p = CapturePrerequisites()
        p.enabled = valid; p.sessionActive = session; p.secureInput = status.secureInput
        p.permissions = status.permissions; p.authenticatedController = controllerUID != 0
        p.driverReady = status.driverReady; p.connectionLeaseValid = config.enabled
        let targets = devices.filter { selected($0) }
        let readyTargets = targets.filter { captureReady($0) }
        p.keysNeutral = lifecycle.phase == .capturing || (!readyTargets.isEmpty && readyTargets.allSatisfy { ($0.observed || $0.seized) && neutral($0) })
        execute(lifecycle.update(p, now: now))
        if !valid || !status.driverReady || lifecycle.phase == .faulted {
            for d in devices where d.observed { IOHIDDeviceClose(d.hid, 0); d.observed = false }
        }
        if !valid {
            for d in devices where d.observed { IOHIDDeviceClose(d.hid, 0); d.observed = false }
            destroyVirtualClient()
        }
        // Allow-listed actions leave the device callback via a small queue.
        let pending = actions; actions.removeAll(keepingCapacity: true)
        if valid && lifecycle.phase == .capturing && !engine.manualPassThrough { for (action, pid, generation) in pending { onAction?(action, pid, generation) } }
        status.capturedDevices = devices.filter { $0.seized }.count; status.eligibleDevices = targets.count
        var deviceStatus = [HIDDeviceStatus]()
        for d in devices {
            if let i = deviceStatus.firstIndex(where: { $0.identity == d.identity }) { deviceStatus[i].captured = deviceStatus[i].captured || d.seized }
            else { deviceStatus.append(.init(identity: d.identity, product: d.product, builtIn: d.builtIn, captured: d.seized)) }
        }
        if status.devices != deviceStatus { status.devices = deviceStatus }
        status.manualPassThrough = engine.manualPassThrough; status.emergencyPaused = engine.emergencyPaused
        status.processed = engine.processed; status.translated = engine.translated; status.maxMicroseconds = maxMicroseconds
        if !fault.isEmpty { status.state = fault }
        else if nativePass && config.enabled { status.state = "原生穿透：\(config.mode.title)；已釋放實體鍵盤" }
        else if !status.permissions { status.state = "等待 WindowsMacBridge 輸入監控權限" }
        else if status.secureInput { status.state = "Secure Input：已釋放裝置" }
        else if !valid { status.state = "已停止擷取" }
        else if !status.driverReady { status.state = "等待 VirtualHID Driver；不擷取鍵盤" }
        else if devices.isEmpty { status.state = "找不到支援的目標鍵盤服務" }
        else if targets.isEmpty { status.state = "已辨識鍵盤均為 Native Mac／不在指定範圍" }
        else { status.state = String(describing: lifecycle.phase) }
        if status != publishedStatus {
            publishedStatus = status; onStatus?(status, config.generation)
        }
        scheduleHeldSafety()
    }
    /// One-shot loss guard (HeldSafetyPolicy): held keys/modifiers/buttons or
    /// reports the driver has not completed (a final key-up or button-up
    /// included). An armed deadline is reused rather than re-allocated per HID
    /// value; it re-arms from tick() only while something is still pending, and a
    /// stalled driver (no completion for 500 ms) makes tick() fail closed.
    private func scheduleHeldSafety() {
        let held = report.modifiers != 0 || report.fn || report.key_count != 0 || report.consumer_count != 0 ||
            report.top_case_count != 0 || report.vendor_count != 0 || report.desktop_count != 0
        let deadline = HeldSafetyPolicy.deadline(
            capturing: config.enabled && devices.contains(where: { $0.seized }), heldOutput: held,
            pointingButtons: pointing.buttons, outstandingReports: client.map { wmb_virtual_hid_outstanding($0) } ?? 0)
        heldSafety.schedule(after: deadline) { [weak self] in self?.tick() }
    }
    private func received(_ result: IOReturn, value: IOHIDValue) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { maxMicroseconds = max(maxMicroseconds, Double(DispatchTime.now().uptimeNanoseconds - started) / 1000) }
        let element = IOHIDValueGetElement(value), hid = IOHIDElementGetDevice(IOHIDValueGetElement(value))
        guard let device = devices.first(where: { $0.hid == hid }) else { return }
        if device.observed && !device.seized { tick(); return }
        guard device.seized else { return }
        defer { scheduleHeldSafety() }
        guard result == kIOReturnSuccess, let role = device.roles[IOHIDElementGetCookie(element)], IOHIDValueGetLength(value) <= 8 else {
            failClose("輸入狀態失效；擷取已停止。"); return
        }
        // Policy gaps (Secure Input, session change, lease) are transient: hand the
        // devices back now and let tick re-evaluate. They are not device faults.
        guard config.enabled, config.sessionActive, consoleSessionValid, !IsSecureEventInputEnabled() else {
            execute(lifecycle.stop()); scheduleTick(); return
        }
        if role.pointing { receivePointing(device, role: role, value: value); return }
        guard let usage = UInt16(exactly: IOHIDElementGetUsage(element)) else { failClose("輸入狀態失效；擷取已停止。"); return }
        let wasPassing = engine.manualPassThrough, wasPaused = engine.emergencyPaused
        let action = engine.observe(device: device.id, page: IOHIDElementGetUsagePage(element),
            usage: usage, down: IOHIDValueGetIntegerValue(value) != 0)
        if wasPassing != engine.manualPassThrough || engine.emergencyPaused { actions.removeAll(keepingCapacity: true) }
        if config.diagnostics, let rule = engine.lastRuleID { status.lastRule = rule }
        if let action {
            if actions.count < 16 { actions.append((action, config.processID, config.actionGeneration)) }
            else { failClose("動作佇列已滿；擷取已停止。"); return }
        }
        sendOutput()
        // The emergency chord must release the seized devices, not leave them mute,
        // and both toggles must reach the App. Only tick() does either.
        if wasPassing != engine.manualPassThrough || wasPaused != engine.emergencyPaused { scheduleTick() }
    }
    private func receivePointing(_ device: Device, role: HIDElementRole, value: IOHIDValue) {
        let element = IOHIDValueGetElement(value), amount = IOHIDValueGetIntegerValue(value)
        if role == .button { flushPointing() } // Motion belongs to the button state before this edge.
        guard pointing.observe(device: device.id, role: role, usage: IOHIDElementGetUsage(element), value: amount) else {
            failClose("複合裝置值超出輸出預算；已釋放。"); return
        }
        if role == .button { flushPointing(force: true); return }
        let field: UInt8 = role == .x ? 1 : role == .y ? 2 : role == .wheel ? 4 : 8
        let timestamp = IOHIDValueGetTimeStamp(value)
        if pointingFields != 0 && (timestamp != pointingTimestamp || pointingFields & field != 0) { flushPointing() }
        pointingTimestamp = timestamp; pointingFields |= field
        switch role { case .x: pendingPointing.x = Int16(amount); case .y: pendingPointing.y = Int16(amount)
        case .wheel: pendingPointing.wheel = Int16(amount); case .pan: pendingPointing.pan = Int16(amount); default: break }
        if !pointingFlushQueued {
            pointingFlushQueued = true
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else { return }; self.pointingFlushQueued = false; self.flushPointing()
            }
        }
    }
    /// Motion may be dropped under backpressure; button state never is.
    static let pointingMotionBacklog: UInt32 = 64
    private func flushPointing(force: Bool = false) {
        guard force || pointingFields != 0 else { return }
        let motion = pendingPointing; pendingPointing = .init(); pointingFields = 0
        // The authenticated XPC lease replaced heartbeats; the old one-second
        // heartbeat clause silently dropped all pointing (and button-up) output.
        guard lifecycle.phase == .capturing, config.enabled, config.sessionActive, consoleSessionValid,
              !failClosed, !engine.emergencyPaused, let client else { return }
        guard wmb_virtual_hid_status(client) & UInt32(WMB_POINTING_READY) != 0 else {
            // Never keep a composite device seized without a pointing output path.
            execute(lifecycle.stop()); scheduleTick(); return
        }
        if !force && wmb_virtual_hid_outstanding(client) > Self.pointingMotionBacklog { return }
        if !wmb_virtual_hid_post_pointing(client, pointing.buttons, motion.x, motion.y, motion.wheel, motion.pan) {
            failClose("複合裝置輸出失效；已釋放。")
        }
    }
    private func sendOutput() {
        guard let client else { return }
        guard engine.render(into: &output) else { failClose("輸出容量超限；擷取已停止。"); return }
        report.modifiers = output.modifiers; report.fn = output.fn
        report.key_count = UInt8(output.keyCount); report.consumer_count = UInt8(output.consumerCount)
        report.top_case_count = UInt8(output.topCaseCount); report.vendor_count = UInt8(output.vendorCount); report.desktop_count = UInt8(output.desktopCount)
        withUnsafeMutableBytes(of: &report.keys) { bytes in output.keys.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.consumer_keys) { bytes in output.consumer.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.top_case_keys) { bytes in output.topCase.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.vendor_keys) { bytes in output.vendor.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        withUnsafeMutableBytes(of: &report.desktop_keys) { bytes in output.desktop.withUnsafeBytes { bytes.copyMemory(from: $0) } }
        if !wmb_virtual_hid_post(client, &report) { failClose("VirtualHID 輸出中斷；已釋放鍵盤。") }
    }
}
