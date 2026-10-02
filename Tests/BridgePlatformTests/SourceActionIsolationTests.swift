import Testing
import Foundation
import BridgeCore
@testable import BridgePlatform

@MainActor private final class DeferredSystemOpener: SystemApplicationOpening {
    var completion: CheckedContinuation<SystemApplicationActivation?, any Error>?
    func open(bundleID: String) async throws -> SystemApplicationActivation? {
        try await withCheckedThrowingContinuation { completion = $0 }
    }
}
private final class ActionTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: Double) { lock.lock(); self.value = value; lock.unlock() }
}

@MainActor struct SourceActionIsolationTests {
    @Test func physicalPreferenceChangeCancelsQueuedLocalActionButKeepsRemoteAction() async throws {
        // A deterministic clock tests source revocation independently of other parallel
        // AppKit image tests occupying the main actor beyond the real 0.6s deadline.
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 })
        let context = ApplicationContext(processID: 123, bundleID: "test", mode: .macOS)
        dispatcher.update(context: context, enabled: true)
        var captures = 0
        dispatcher.onScreenshot = { _, _ in captures += 1 }
        #expect(dispatcher.submit(.screenshot(.region), context: context))
        let remote = SourceWorkToken(origin: .init(), frame: .init())
        #expect(dispatcher.submit(.screenshot(.region), context: context, source: remote))
        dispatcher.cancelLocalPending()
        for _ in 0..<100 where captures != 1 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(captures == 1 && remote.isCurrent)
        #expect(dispatcher.submit(.screenshot(.region), context: context))
        for _ in 0..<100 where captures != 2 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(captures == 2)
    }
    @Test func pauseAndSourceRevocationRejectQueuedWorkAndMailboxRemainsBounded() async {
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true })
        let context = ApplicationContext(processID: 123, bundleID: "test", mode: .macOS)
        dispatcher.update(context: context, enabled: true)
        var captures = 0
        dispatcher.onScreenshot = { _, _ in captures += 1 }
        let origin = SourceWorkGate()
        #expect(dispatcher.submit(.screenshot(.region), context: context, source: .init(origin: origin, frame: .init())))
        origin.invalidate()
        for _ in 0..<20 { await Task.yield() }
        #expect(captures == 0)
        for _ in 0..<16 { #expect(dispatcher.submit(.screenshot(.region), context: context)) }
        #expect(!dispatcher.submit(.screenshot(.region), context: context))
        dispatcher.cancelPending(disable: true)
        for _ in 0..<20 { await Task.yield() }
        #expect(captures == 0 && dispatcher.rejectedCount == 1)
    }
    @Test func systemAppFinishedAfterPauseCannotActivateOrPublishStaleResult() async throws {
        let opener = DeferredSystemOpener()
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 }, systemOpener: opener)
        let context = ApplicationContext(processID: 123, bundleID: "test", mode: .macOS)
        dispatcher.update(context: context, enabled: true)
        var activations = 0
        #expect(dispatcher.submit(.system(.openSettings), context: context))
        for _ in 0..<100 where opener.completion == nil { try await Task.sleep(for: .milliseconds(2)) }
        let completion = try #require(opener.completion)
        dispatcher.cancelPending(disable: true)
        completion.resume(returning: .init { activations += 1 })
        opener.completion = nil
        for _ in 0..<100 where dispatcher.hasPendingWork { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!dispatcher.hasPendingWork && activations == 0 && dispatcher.status().isEmpty)
    }
    @Test func systemLaunchAllowsBoundedStartupWithoutExtendingKeyboardActionDeadline() async throws {
        let opener = DeferredSystemOpener(), clock = ActionTestClock()
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { clock.read() }, systemOpener: opener)
        let context = ApplicationContext(processID: 123, bundleID: "test", mode: .macOS)
        dispatcher.update(context: context, enabled: true)
        var activations = 0, captures = 0
        dispatcher.onScreenshot = { _, _ in captures += 1 }
        for (start, finish, expected) in [(0.0,1.0,1), (2.0,20.0,1)] {
            clock.set(start)
            #expect(dispatcher.submit(.system(.openSettings), context: context))
            for _ in 0..<100 where opener.completion == nil { try await Task.sleep(for: .milliseconds(2)) }
            let completion = try #require(opener.completion)
            clock.set(finish); completion.resume(returning: .init { activations += 1 }); opener.completion = nil
            for _ in 0..<100 where dispatcher.hasPendingWork { try await Task.sleep(for: .milliseconds(2)) }
            #expect(!dispatcher.hasPendingWork && activations == expected)
        }
        #expect(dispatcher.submit(.screenshot(.region), context: context))
        clock.set(21)
        for _ in 0..<100 where dispatcher.hasPendingWork { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!dispatcher.hasPendingWork && captures == 0)
    }
}
