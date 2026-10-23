import Foundation
import ApplicationServices
import Testing
import BridgeCore
@testable import BridgePlatform

private actor DeferredTerminalSelection {
    var continuation: CheckedContinuation<TerminalSelectionState, Never>?
    var ready: Bool { continuation != nil }
    func read() async -> TerminalSelectionState {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: .empty); continuation = nil }
}
private actor TerminalSelectionCounter {
    var calls = 0
    func read() -> TerminalSelectionState { calls += 1; return .empty }
}
private final class TerminalCopyClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    func expire() { lock.lock(); value = 1; lock.unlock() }
}

@MainActor struct TerminalCopyTests {
    private let context = ApplicationContext(processID: 123, bundleID: "test.terminal", mode: .terminal)
    private func wait(_ dispatcher: ShortcutActionDispatcher) async throws {
        for _ in 0..<100 where dispatcher.hasPendingWork { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!dispatcher.hasPendingWork)
    }

    @Test(arguments: TerminalSelectionState.allCases)
    func legacyTerminalActionAlwaysCopiesWithoutInspectingSelection(state: TerminalSelectionState) async throws {
        var output: [Modifiers] = []
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
            terminalSelection: { _ in state }, terminalKeyEmitter: { key, flags, target in
                #expect(key == 8 && target.mode == .terminal); output.append(flags); return true
            })
        dispatcher.update(context: context, enabled: true)
        #expect(dispatcher.submit(.terminalCopyOrInterrupt, context: context))
        try await wait(dispatcher)
        #expect(output == [.command])
        #expect(dispatcher.status().isEmpty)
    }

    @Test(arguments: ["pause", "local", "permission", "context", "deadline", "source"])
    func staleSelectionNeverInterruptsAfterWorkIsRevoked(change: String) async throws {
        let reader = DeferredTerminalSelection(), clock = TerminalCopyClock()
        var authorized = true, output: [Modifiers] = []
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in authorized }, clock: { clock.read() },
            terminalSelection: { _ in await reader.read() }, terminalKeyEmitter: { _, flags, _ in output.append(flags); return true })
        dispatcher.update(context: context, enabled: true)
        let origin = SourceWorkGate()
        let source: SourceWorkToken? = change == "source" ? .init(origin: origin, frame: .init()) : nil
        #expect(dispatcher.submit(.terminalCopyOrInterrupt, context: context, source: source))
        switch change {
        case "pause": dispatcher.cancelPending(disable: true)
        case "local": dispatcher.cancelLocalPending()
        case "permission": authorized = false
        case "context": dispatcher.update(context: .init(processID: 456, mode: .terminal), enabled: true)
        case "deadline": clock.expire()
        default: origin.invalidate()
        }
        try await wait(dispatcher)
        #expect(output.isEmpty && dispatcher.status().isEmpty)
    }

    @Test func nonTerminalCannotRequestSelectionAwareInterrupt() async throws {
        let reader = TerminalSelectionCounter()
        var emitted = false
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
            terminalSelection: { _ in await reader.read() }, terminalKeyEmitter: { _, _, _ in emitted = true; return true })
        // A non-Terminal action is rejected before any AX read or key emission.
        let other = ApplicationContext(processID: 123, mode: .ide)
        dispatcher.update(context: other, enabled: true)
        #expect(dispatcher.submit(.terminalCopyOrInterrupt, context: other))
        try await wait(dispatcher)
        #expect(!emitted)
        #expect(await reader.calls == 0)
    }

    @Test func rangesRequirePositiveEvidenceBeforeInterrupting() {
        #expect(TerminalSelectionReader.classify([]) == .empty)
        #expect(TerminalSelectionReader.classify([CFRange(location: 10, length: 0)]) == .empty)
        #expect(TerminalSelectionReader.classify([CFRange(location: 10, length: 0), CFRange(location: 50, length: 3)]) == .selected)
        for range in [CFRange(location: -1, length: 0), CFRange(location: NSNotFound, length: 0),
                      CFRange(location: 0, length: -1), CFRange(location: Int.max - 1, length: 3)] {
            #expect(TerminalSelectionReader.classify([range]) == .unknown)
        }
        #expect(TerminalSelectionReader.classify(Array(repeating: CFRange(location: 0, length: 0), count: 17)) == .unknown)
    }

    @Test func rangeDecoderRejectsTextAndOtherAXValueTypes() throws {
        var range = CFRange(location: 10, length: 3), point = CGPoint(x: 1, y: 2)
        let value = try #require(AXValueCreate(.cfRange, &range))
        let decoded = try #require(TerminalSelectionReader.range(value))
        #expect(decoded.location == 10 && decoded.length == 3)
        #expect(TerminalSelectionReader.range("not a range" as CFString)?.location == nil)
        let pointValue = try #require(AXValueCreate(.cgPoint, &point))
        #expect(TerminalSelectionReader.range(pointValue)?.location == nil)
    }
}
