/// Backend-neutral ownership model for a future device capture / virtual HID adapter.
/// The CGEventTap adapter must not use this ledger without device identity.
public enum HIDModifier: Int, CaseIterable, Sendable {
    case leftControl, rightControl, leftCommand, rightCommand
    case leftOption, rightOption, leftShift, rightShift, fn
    public var bit: UInt16 { 1 << rawValue }
    public var windowsMapping: Self {
        switch self {
        case .fn: .leftControl
        case .leftControl: .fn
        case .leftOption: .leftCommand
        case .rightOption: .rightCommand
        case .leftCommand: .leftOption
        case .rightCommand: .rightOption
        default: self
        }
    }
}

public struct HIDCaptureGate: Sendable {
    public var virtualKeyboardReady = false
    public var permissionsGranted = false
    public var sessionActive = false
    public var secureInput = true
    public var physicalKeysNeutral = false
    public init() {}
    public var maySeize: Bool {
        virtualKeyboardReady && permissionsGranted && sessionActive && !secureInput && physicalKeysNeutral
    }
}

/// Fixed capacity. Each physical modifier owns its own output until release or invalidation.
/// Disconnecting one keyboard cannot release an output still owned by another keyboard.
public struct HIDModifierLedger: Sendable {
    public static let capacity = 16
    private static let modifierCount = 9
    private var devices = [UInt64?](repeating: nil, count: capacity)
    private var physical = [UInt16](repeating: 0, count: capacity)
    private var suppressed = [UInt16](repeating: 0, count: capacity)
    private var outputs = [UInt16](repeating: 0, count: capacity * modifierCount)
    private var mappingEnabled = true
    public init() {}
    @discardableResult public mutating func register(_ device: KeyboardDevice) -> Bool {
        guard device.matchesRequestedScope else { return false }
        if devices.contains(device.registryID) { return true }
        guard let slot = devices.firstIndex(of: nil) else { return false }
        devices[slot] = device.registryID
        return true
    }
    public var reportModifiers: UInt16 { outputs.reduce(0, |) }
    public var heldPhysicalModifiers: UInt16 { physical.reduce(0, |) }
    /// Caller sends the resulting report before releasing the device or stopping output.
    public mutating func disconnect(_ deviceID: UInt64) {
        guard let slot = devices.firstIndex(of: deviceID) else { return }
        clearOutputs(slot)
        physical[slot] = 0; suppressed[slot] = 0; devices[slot] = nil
    }
    public mutating func transition(mappingEnabled: Bool) {
        self.mappingEnabled = mappingEnabled
        // A translated hold cannot migrate into a newly focused remote app.
        for slot in devices.indices {
            suppressed[slot] = physical[slot]
            clearOutputs(slot)
        }
    }
    public mutating func observe(deviceID: UInt64, modifier: HIDModifier, down: Bool) {
        guard let slot = devices.firstIndex(of: deviceID) else { return }
        let index = slot * Self.modifierCount + modifier.rawValue
        if down {
            guard physical[slot] & modifier.bit == 0 else { return }
            physical[slot] |= modifier.bit
            // After a context gap, wait for all physical modifiers to be released.
            if suppressed.contains(where: { $0 != 0 }) {
                suppressed[slot] |= modifier.bit
                return
            }
            outputs[index] = (mappingEnabled ? modifier.windowsMapping : modifier).bit
        } else {
            physical[slot] &= ~modifier.bit
            suppressed[slot] &= ~modifier.bit
            outputs[index] = 0
        }
    }
    private mutating func clearOutputs(_ slot: Int) {
        for key in 0..<Self.modifierCount { outputs[slot * Self.modifierCount + key] = 0 }
    }
}
