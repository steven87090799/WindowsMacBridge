import Foundation
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor private final class KeyboardBackendFixture: MacBookKeyboardMappingBackend {
    var portable = true
    var bootID = "test-boot-1"
    var rows: [MacBookKeyboardService] = [MacBookKeyboardService(identity:
        MacBookKeyboardIdentity(registryID: 1, builtIn: true, vendorID: 1452, transport: "SPI",
                                product: "Apple Internal Keyboard / Trackpad"), userMapping: [])]
    var writes: [(UInt64, [NativeKeyMapping])] = []
    var acceptWrite = true, lieAboutWrite = false, acceptObservation = true
    var inventoryAvailable = true
    var change: (@MainActor () -> Void)?
    func services() -> [MacBookKeyboardService]? { inventoryAvailable ? rows : nil }
    func write(_ mapping: [NativeKeyMapping], serviceID: UInt64) -> Bool {
        writes.append((serviceID, mapping))
        guard acceptWrite, let i = rows.firstIndex(where: { $0.identity.registryID == serviceID }) else { return false }
        if !lieAboutWrite { rows[i].userMapping = mapping }
        return true
    }
    func observeChanges(_ action: @escaping @MainActor () -> Void) -> Bool {
        if acceptObservation { change = action }
        return acceptObservation
    }
    func stopObserving() { change = nil }
}

@MainActor struct MacBookKeyboardMapperTests {
    private func defaults() -> (String, UserDefaults) {
        let name = "WindowsMacBridge.Tests.FnControl." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }
    @Test func nativeSwapIsVerifiedAndTurningOffRestoresOriginalOnly() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let other = NativeKeyMapping(0x700000039, 0x700000029)
        backend.rows[0].userMapping = [other]
        backend.rows.append(MacBookKeyboardService(identity: MacBookKeyboardIdentity(registryID: 2,
            builtIn: false, vendorID: 1133, transport: "USB", product: "External keyboard"), userMapping: []))
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        #expect(mapper.status.activeDevices == 1 && mapper.status.issue == nil)
        #expect(backend.rows[0].userMapping == [other] + MacBookFnControlMapping.swap)
        #expect(backend.rows[1].userMapping == [])
        mapper.configure(enabled: false)
        #expect(backend.rows[0].userMapping == [other] && mapper.status.activeDevices == 0)
        #expect(defaults.object(forKey: "macbook.fnControl.journal.v1") == nil)
    }
    @Test func universalControlAndExternalKeyboardsNeverGetChangedOnEitherMac() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        backend.rows[0].identity.product = "V-Apple Internal Keyboard / Trackpad"
        backend.rows.append(MacBookKeyboardService(identity: MacBookKeyboardIdentity(registryID: 2,
            builtIn: false, vendorID: 1452, transport: "USB", product: "Magic Keyboard"), userMapping: []))
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        #expect(backend.writes.isEmpty && mapper.status.activeDevices == 0)
        backend.rows[0].identity.product = "Apple Internal Keyboard / Trackpad"
        backend.portable = false; mapper.refresh()
        #expect(backend.writes.isEmpty)
    }
    @Test func setterSuccessIsNotReportedAsWorkingWithoutReadback() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture(); backend.lieAboutWrite = true
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        #expect(mapper.status.activeDevices == 0 && mapper.status.issue != nil)
        #expect(backend.rows[0].userMapping == [])
    }
    @Test func conflictsAndUnknownPropertyFormatsFailClosed() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        backend.rows[0].modifierMapping = [NativeKeyMapping(MacBookFnControlMapping.leftControl, 0x7000000e3)]
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        #expect(backend.writes.isEmpty && mapper.status.issue != nil)
        backend.rows[0].modifierMapping = []; backend.rows[0].userMapping = nil; mapper.refresh()
        #expect(backend.writes.isEmpty && mapper.status.issue != nil)
        backend.rows[0].userMapping = [NativeKeyMapping(MacBookFnControlMapping.fn, 0x7000000e3)]; mapper.refresh()
        #expect(backend.writes.isEmpty && mapper.status.issue != nil)
    }
    @Test func sessionAndHIDTransitionRestoreRatherThanSwapTwice() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let active = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        active.configure(enabled: true)
        active.configure(enabled: true, sessionActive: false)
        #expect(backend.rows[0].userMapping == [])
        active.configure(enabled: true)
        #expect(active.status.activeDevices == 1)
        active.configure(enabled: true, eventTapBackend: false)
        #expect(backend.rows[0].userMapping == [] && active.status.activeDevices == 0)
        active.stop()
    }
    @Test func crashJournalRecoversOnNextLaunchAndNewBootDoesNotReuseOldOwnership() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let previous = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        previous.configure(enabled: true)
        let restarted = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        restarted.configure(enabled: true)
        #expect(restarted.status.activeDevices == 1 && backend.writes.count == 1)
        restarted.stop()
        #expect(backend.rows[0].userMapping == [])
        previous.configure(enabled: true)
        backend.bootID = "test-boot-2"
        // A reboot removed service properties. Preserve a new unrelated remapping with the same numeric ID.
        let newMapping = NativeKeyMapping(MacBookFnControlMapping.fn, 0x7000000e3)
        backend.rows[0].userMapping = [newMapping]
        let newBoot = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        newBoot.configure(enabled: false)
        #expect(backend.rows[0].userMapping == [newMapping])
    }
    @Test func deviceNotificationReappliesLostPropertyWithoutPolling() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let active = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        active.configure(enabled: true)
        backend.rows[0].userMapping = []; backend.change?()
        #expect(active.status.activeDevices == 1 && backend.writes.count == 2)
        active.refresh()
        #expect(backend.writes.count == 2)
        active.stop()
    }
    @Test func externalEditDuringLeaseIsPreservedAndOwnedRemainderRemoved() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        let external = NativeKeyMapping(MacBookFnControlMapping.leftControl, 0x7000000e3)
        backend.rows[0].userMapping = MacBookFnControlMapping.swap.filter { $0.source != external.source } + [external]
        mapper.refresh()
        #expect(backend.rows[0].userMapping == [external] && mapper.status.activeDevices == 0 && mapper.status.issue != nil)
        mapper.stop()
    }
    @Test func failedObservationAndFailedSetterNeverActivateMapping() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        backend.acceptObservation = false
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        #expect(backend.writes.isEmpty && mapper.status.activeDevices == 0 && mapper.status.issue != nil)
        backend.acceptObservation = true; backend.acceptWrite = false
        mapper.configure(enabled: true)
        #expect(mapper.status.activeDevices == 0 && mapper.status.issue != nil)
    }
    @Test func nativePropertyDecoderRejectsMalformedOrDuplicatePairs() {
        let source = "HIDKeyboardModifierMappingSrc", destination = "HIDKeyboardModifierMappingDst"
        let pair = [source: NSNumber(value: MacBookFnControlMapping.fn),
                    destination: NSNumber(value: MacBookFnControlMapping.leftControl)]
        #expect(NativeMacBookKeyboardBackend.decode(nil) == [])
        #expect(NativeMacBookKeyboardBackend.decode([pair]) == [MacBookFnControlMapping.swap[0]])
        #expect(NativeMacBookKeyboardBackend.decode([pair, pair]) == nil)
        #expect(NativeMacBookKeyboardBackend.decode("not a map") == nil)
        #expect(NativeMacBookKeyboardBackend.decode([[source: "bad", destination: NSNumber(value: 3)]]) == nil)
        #expect(NativeMacBookKeyboardBackend.decode([[source: NSNumber(value: -1), destination: NSNumber(value: 3)]]) == nil)
        #expect(NativeMacBookKeyboardBackend.decode([[source: NSNumber(value: 3), destination: NSNumber(value: 4), "extra": 5]]) == nil)
    }
    @Test func unavailableInventoryKeepsRecoveryJournalUntilRestoreCanBeVerified() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        backend.inventoryAvailable = false; mapper.configure(enabled: false)
        #expect(mapper.status.issue != nil && mapper.status.restorePending && defaults.data(forKey: "macbook.fnControl.journal.v1") != nil)
        backend.inventoryAvailable = true; mapper.refresh()
        #expect(backend.rows[0].userMapping == [] && defaults.object(forKey: "macbook.fnControl.journal.v1") == nil)
    }
    @Test func failedRestoreBlocksHIDUntilOwnedMappingIsActuallyRemoved() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        backend.acceptWrite = false
        mapper.configure(enabled: true, eventTapBackend: false)
        #expect(mapper.status.restorePending && mapper.status.issue != nil && mapper.status.activeDevices == 0)
        #expect(backend.rows[0].userMapping == MacBookFnControlMapping.swap)
        #expect(defaults.data(forKey: "macbook.fnControl.journal.v1") != nil)
        backend.acceptWrite = true; mapper.refresh()
        #expect(!mapper.status.restorePending && mapper.status.issue == nil && backend.rows[0].userMapping == [])
    }
    @Test func removedServiceOwnershipIsNotTransferredToReconnectedKeyboard() {
        let (name, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = KeyboardBackendFixture()
        let original = backend.rows[0]
        let mapper = MacBookKeyboardMapper(backend: backend, defaults: defaults)
        mapper.configure(enabled: true)
        backend.rows = []; backend.change?()
        #expect(mapper.status.activeDevices == 0 && defaults.object(forKey: "macbook.fnControl.journal.v1") == nil)
        var reconnected = original; reconnected.identity.registryID = 3
        backend.rows = [reconnected]; backend.change?()
        #expect(mapper.status.activeDevices == 1 && backend.writes.last?.0 == 3)
        mapper.stop()
        #expect(backend.rows[0].userMapping == [])
    }
}
