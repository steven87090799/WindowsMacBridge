// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Carbon
import Foundation
import BridgeCore

final class HotkeyManager {
    var onHotkey: (() -> Void)?
    private var eventHandler: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var activePreset: HotkeyPreset?
    private let events = DeferredSignalMailbox()

    var isRegistered: Bool { hotKeyReference != nil }

    init() {
        installEventHandler()
    }
    deinit { stop() }

    @discardableResult
    func register(_ preset: HotkeyPreset) -> OSStatus {
        guard eventHandler != nil else { return OSStatus(eventNotHandledErr) }
        if activePreset == preset, hotKeyReference != nil {
            return noErr
        }

        let previousPreset = activePreset
        events.invalidate()
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        let status = registerReference(for: preset)
        if status == noErr {
            activePreset = preset
            FileLogger.shared.log("Global hotkey registered: \(preset.title)")
            return status
        }

        FileLogger.shared.log("Global hotkey registration failed (OSStatus \(status)): \(preset.title)")
        activePreset = nil

        if let previousPreset {
            let rollbackStatus = registerReference(for: previousPreset)
            if rollbackStatus == noErr {
                activePreset = previousPreset
                FileLogger.shared.log("Restored previous global hotkey after failed replacement: \(previousPreset.title)")
            } else {
                FileLogger.shared.log(
                    "Unable to restore previous global hotkey (OSStatus \(rollbackStatus)): \(previousPreset.title)"
                )
            }
        }

        return status
    }

    func discardPending() { events.invalidate() }

    func suspend() {
        events.invalidate()
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        activePreset = nil
    }

    func stop() {
        suspend()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func registerReference(for preset: HotkeyPreset) -> OSStatus {
        let identifier = EventHotKeyID(signature: OSType(0x56434744), id: 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            preset.eventKeyCode,
            preset.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeyReference = reference
        }
        return status
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleCarbonEvent,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        if status != noErr {
            FileLogger.shared.log("Global hotkey event handler installation failed (OSStatus \(status))")
        }
    }

    private static let handleCarbonEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, identifier.signature == OSType(0x56434744), identifier.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        guard manager.events.offer(1) else { return noErr }
        DispatchQueue.main.async { [weak manager] in
            guard let manager, manager.events.take() != 0, manager.isRegistered else { return }
            manager.onHotkey?()
        }
        return noErr
    }
}
