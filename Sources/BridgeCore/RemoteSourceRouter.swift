/// Input-thread confined, fixed 16 streams; source state never touches physical HID state.
public struct RemoteSourceRouter: Sendable {
    private struct Stream: Sendable {
        var producer: RemoteProducer
        var stateID: Int64
        var processor = KeyboardEventProcessor()
        var frame = SourceWorkGate()
        var fresh = true
        var appSwitchHeld = false
        var appSwitchKey: UInt16 = 55
        var lastEventAt: Double = 0
    }
    private var slots = [Stream?](repeating: nil, count: 16)
    private var snapshot = InputRoutingSnapshot()
    private var configuration = SourceTranslationConfiguration()
    public private(set) var processedCount: UInt64 = 0, translatedCount: UInt64 = 0
    public init() {}
    public mutating func update(_ snapshot: InputRoutingSnapshot, configuration: SourceTranslationConfiguration,
                                release: (UInt16, Modifiers, Int32) -> Void = { _,_,_ in }) {
        for i in slots.indices {
            guard var stream = slots[i] else { continue }
            let replacement = snapshot.producers.first { $0.processID == stream.producer.processID }
            if replacement != stream.producer || self.configuration != configuration {
                stream.processor.drainTranslatedReleases(release)
                if stream.appSwitchHeld { release(stream.appSwitchKey, [], self.configuration.context.processID); stream.appSwitchHeld = false }
                stream.processor.invalidate(); stream.frame.invalidate(); stream.frame = SourceWorkGate()
                // A changed source session also invalidates detached AX/screenshot work immediately.
                if replacement != stream.producer { stream.producer.work.invalidate() }
                guard let replacement else { slots[i] = nil; continue }
                stream.producer = replacement
                configure(&stream.processor, producer: replacement, config: configuration)
                slots[i] = stream
            }
        }
        self.snapshot = snapshot; self.configuration = configuration
    }
    public mutating func invalidate(release: (UInt16, Modifiers, Int32) -> Void = { _,_,_ in }) {
        for i in slots.indices where slots[i] != nil {
            slots[i]!.processor.drainTranslatedReleases(release)
            if slots[i]!.appSwitchHeld { release(slots[i]!.appSwitchKey, [], configuration.context.processID); slots[i]!.appSwitchHeld = false }
            slots[i]!.processor.invalidate(); slots[i]!.frame.invalidate(); slots[i]!.frame = SourceWorkGate()
        }
    }
    private func configure(_ processor: inout KeyboardEventProcessor, producer: RemoteProducer, config: SourceTranslationConfiguration) {
        processor.configure(context: config.context, enabled: config.enabled && producer.semantics != .macOS && producer.semantics != .alreadyTranslated,
                            layoutSupported: config.layoutSupported, controlsEnabled: false,
                            finderEnabled: config.finderEnabled, finderPermanentDeleteEnabled: config.finderPermanentDeleteEnabled,
                            textNavigationEnabled: config.textNavigationEnabled, altF4Enabled: config.altF4Enabled,
                            windowsKeyModifier: .command, winRunEnabled: config.winRunEnabled,
                            winSettingsEnabled: config.winSettingsEnabled, winTaskViewEnabled: config.winTaskViewEnabled,
                            nativeAppSwitchEnabled: true, screenshotEnabled: config.screenshotEnabled, printScreen: config.printScreen)
    }
    /// Conservative loss guard: only this producer's translated outputs are released.
    /// Reuses lifecycle observation; no extra polling timer or global physical-key reset.
    public mutating func expire(at now: Double, release: (UInt16, Modifiers, Int32) -> Void) {
        for i in slots.indices where slots[i] != nil {
            guard now >= slots[i]!.lastEventAt, now - slots[i]!.lastEventAt >= 60,
                  slots[i]!.processor.activePressCount > 0 || !slots[i]!.processor.modifiers.aggregate.isEmpty || slots[i]!.appSwitchHeld else { continue }
            slots[i]!.processor.drainTranslatedReleases(release)
            if slots[i]!.appSwitchHeld { release(slots[i]!.appSwitchKey, [], configuration.context.processID); slots[i]!.appSwitchHeld = false }
            slots[i]!.processor.invalidate(); slots[i]!.frame.invalidate(); slots[i]!.frame = SourceWorkGate()
            slots[i]!.lastEventAt = now
        }
    }
    public mutating func process(_ original: KeyboardEvent, evidence: InputOriginEvidence, now: Double = 0) -> RoutedInputDecision {
        guard case .remote(let producerIndex) = snapshot.classify(evidence, physicalBackend: .deviceHID) else { return .init() }
        let producer = snapshot.producers[producerIndex]
        guard producer.work.isCurrentWithoutWaiting else { return .init() }
        let existing = slots.firstIndex { $0?.producer == producer && $0?.stateID == evidence.stateID }
        guard let index = existing ?? slots.firstIndex(where: { $0 == nil }) else { return .init() }
        if existing == nil {
            var stream = Stream(producer: producer, stateID: evidence.stateID)
            configure(&stream.processor, producer: producer, config: configuration)
            slots[index] = stream
        }
        var event = original
        slots[index]!.lastEventAt = now
        if event.phase == .flagsChanged, let side = event.modifierSide {
            // Side transitions are derived from this source's history, not aggregate CG state.
            let groupPresent = event.modifiers.contains(side.group)
            let down = event.modifierDown ?? (groupPresent && !slots[index]!.processor.modifiers.isDown(side))
            event.modifierDown = down
            if !producer.independentFlags {
                var ownFlags = slots[index]!.processor.modifiers.aggregate
                if down { ownFlags.insert(side.group) }
                else if !slots[index]!.processor.modifiers.isDown(side.peer) { ownFlags.remove(side.group) }
                event.modifiers = ownFlags
            }
            if slots[index]!.fresh && down && event.modifiers.subtracting(.fn) == side.group {
                slots[index]!.processor.reconcileNeutralHardware(); slots[index]!.fresh = false
            }
        } else if producer.independentFlags {
            slots[index]!.processor.reconcileIndependentSourceFlags(event.modifiers)
        } else {
            // Aggregate CG flags may include local/other sources. An explicit generic
            // override trusts this PID's modifier edges, never another keyboard's flags.
            event.modifiers = slots[index]!.processor.modifiers.aggregate
        }
        switch producer.semantics {
        case .windows: event.allowsTranslation = true
        case .macOS, .alreadyTranslated: event.allowsTranslation = false
        case .automatic:
            // Raw Control is strong evidence. Command chords and ambiguous Option navigation
            // are already valid Mac input, so automatic mode never converts them again.
            event.allowsTranslation = producer.confidence == .known && producer.transport == .googleRemoteDesktop &&
                (!event.modifiers.contains(.command) && (event.modifiers.contains(.control) || event.modifiers.subtracting(.shift).isEmpty ||
                 (event.modifiers.subtracting(.shift) == .option && (event.keyCode == 48 || event.keyCode == 118 || event.keyCode == 105))))
        }
        var decision = slots[index]!.processor.process(event)
        processedCount &+= 1
        if event.phase == .down && !event.isRepeat {
            if case .rewrite = decision { translatedCount &+= 1 }
            else if case .action = decision { translatedCount &+= 1 }
        }
        if case .rewrite(_, _, "windows.nativeAppSwitch") = decision, event.phase == .down {
            if !slots[index]!.appSwitchHeld {
                let state = slots[index]!.processor.modifiers
                slots[index]!.appSwitchKey = state.isDown(.rightOption) && !state.isDown(.leftOption) ? 54 : 55
            }
            slots[index]!.appSwitchHeld = true
        }
        if slots[index]!.appSwitchHeld {
            let flags = event.modifiers.subtracting(.option).union(event.modifiers.contains(.option) ? .command : [])
            if event.phase == .flagsChanged {
                let key = event.modifierSide == .rightOption || event.modifierSide == .leftOption ? slots[index]!.appSwitchKey : event.keyCode
                decision = .rewrite(keyCode: key, modifiers: flags, ruleID: "windows.nativeAppSwitch.modifier")
            } else if decision == .passThrough {
                decision = .rewrite(keyCode: event.keyCode, modifiers: flags, ruleID: "windows.nativeAppSwitch.held")
            }
            if !event.modifiers.contains(.option) { slots[index]!.appSwitchHeld = false }
        }
        return .init(decision, validity: .init(origin: producer.work, frame: slots[index]!.frame,
                                              producerProcessID: producer.processID, producerSession: producer.session))
    }
    public mutating func rejectAction(keyCode: UInt16, evidence: InputOriginEvidence) {
        guard let index = slots.firstIndex(where: { $0?.producer.processID == evidence.processID && $0?.stateID == evidence.stateID }) else { return }
        slots[index]!.processor.rejectAction(keyCode: keyCode)
    }
}
