/// Pure lifecycle contract. A physical capture adapter must execute these commands in order.
/// No state transition here opens or seizes an IOHIDDevice by itself.
public enum CapturePhase: Equatable, Sendable {
    case inactive, waitingForDriver, waitingForNeutral, readyToCapture, capturing, faulted
}
public enum CaptureCommand: Equatable, Sendable {
    case releaseVirtualOutputs, closePhysicalDevices, openPhysicalDevices
}
public struct CapturePrerequisites: Sendable {
    public var sessionActive = false
    public var secureInput = true
    public var permissions = false
    public var authenticatedController = false
    public var driverReady = false
    public var keysNeutral = false
    public var enabled = false
    public var lastHeartbeat: Double = 0
    // A service-owned authenticated XPC connection replaces idle heartbeats.
    // The adapter must close devices on invalidation/interruption.
    public var connectionLeaseValid = false
    public init() {}
    public func leaseValid(at now: Double) -> Bool {
        authenticatedController && (connectionLeaseValid || (now >= lastHeartbeat && now - lastHeartbeat < 1))
    }
}
public struct CaptureLifecycle: Sendable {
    public private(set) var phase: CapturePhase = .inactive
    private var mayOwnDevices = false
    private var faulted = false
    public init() {}
    public mutating func update(_ requirements: CapturePrerequisites, now: Double) -> [CaptureCommand] {
        let eligible = requirements.enabled && requirements.sessionActive && !requirements.secureInput &&
            requirements.permissions && requirements.leaseValid(at: now)
        if faulted || !eligible || !requirements.driverReady {
            let cleanup = release()
            phase = faulted ? .faulted : eligible ? .waitingForDriver : .inactive
            return cleanup
        }
        if phase == .capturing || phase == .readyToCapture { return [] }
        guard requirements.keysNeutral else { phase = .waitingForNeutral; return [] }
        // Set ownership before opening: a partially failed open must still be closed.
        mayOwnDevices = true
        phase = .readyToCapture
        return [.openPhysicalDevices]
    }
    public mutating func captureCompleted(success: Bool) -> [CaptureCommand] {
        guard phase == .readyToCapture else { return [] }
        if success { phase = .capturing; return [] }
        faulted = true; phase = .faulted
        return release()
    }
    /// A key pressed in the observation/seize gap is not a device fault: release
    /// and wait for neutral again. The adapter bounds consecutive aborts and
    /// reports a fault after that, so a flapping element cannot spin.
    public mutating func captureAborted() -> [CaptureCommand] {
        guard phase == .readyToCapture else { return [] }
        phase = .waitingForNeutral
        return release()
    }
    public mutating func stop() -> [CaptureCommand] {
        phase = .inactive
        return release()
    }
    public mutating func deviceRemoved(remainingCaptured: Bool) -> [CaptureCommand] {
        remainingCaptured ? [] : stop()
    }
    public mutating func restart() -> [CaptureCommand] {
        let cleanup = stop()
        faulted = false
        return cleanup
    }
    private mutating func release() -> [CaptureCommand] {
        guard mayOwnDevices else { return [] }
        mayOwnDevices = false
        // Attempt empty reports first; always close physical devices even if the driver is gone.
        return [.releaseVirtualOutputs, .closePhysicalDevices]
    }
}
