import AppKit
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor private final class DeferredClipboardSystemOpener: SystemApplicationOpening {
    private var continuation: CheckedContinuation<SystemApplicationActivation?, Never>?
    var ready: Bool { continuation != nil }
    func open(bundleID: String) async throws -> SystemApplicationActivation? {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: nil); continuation = nil }
}

private actor DeferredClipboardFinderFocus {
    private var continuation: CheckedContinuation<FinderFocus, Never>?
    var ready: Bool { continuation != nil }
    func read() async -> FinderFocus {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ focus: FinderFocus) { continuation?.resume(returning: focus); continuation = nil }
}

private final class ClipboardDeadlineClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    func expire() { lock.lock(); value = 1; lock.unlock() }
}

/// Private pasteboards and injected emitters keep file-move tests away from
/// the user's clipboard, Finder windows, files and global keyboard stream.
@MainActor struct FinderClipboardReliabilityTests {
    private let context = ApplicationContext(processID: 123, bundleID: "com.apple.finder", mode: .macOS)
    private func wait(_ dispatcher: ShortcutActionDispatcher) async throws {
        for _ in 0..<500 where dispatcher.hasPendingWork { try await Task.sleep(for: .milliseconds(2)) }
        #expect(!dispatcher.hasPendingWork)
    }

    @Test func expiredFileMoveRequestStillPerformsOrdinaryPasteWhileItsContextIsCurrent() async throws {
        let clock = ClipboardDeadlineClock(), board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var output: [Modifiers] = []
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { clock.read() },
            keyEmitter: { key, flags, _ in #expect(key == 9); output.append(flags); return true },
            finderPasteboard: { board }, finderFocus: { _ in Issue.record("Expired work must not query Finder"); return .unknown })
        dispatcher.update(context: context, enabled: true, finderEnabled: true)
        #expect(dispatcher.submit(.finder(.cut), context: context))
        #expect(dispatcher.submit(.finder(.paste), context: context))
        clock.expire()
        try await wait(dispatcher)
        #expect(output == [.command] && !dispatcher.hasPendingFinderCut)
    }

    @Test func pasteDoesNotWaitForAnUnrelatedSystemAppToLaunch() async throws {
        let opener = DeferredClipboardSystemOpener()
        var output: [Modifiers] = []
        let board = NSPasteboard.withUniqueName()
        defer { opener.finish(); board.releaseGlobally() }
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
            systemOpener: opener, keyEmitter: { key, flags, _ in
                #expect(key == 9); output.append(flags); return true
            }, finderPasteboard: { board })
        dispatcher.update(context: context, enabled: true, finderEnabled: true)
        #expect(dispatcher.submit(.system(.openSettings), context: context))
        for _ in 0..<500 where !opener.ready { try await Task.sleep(for: .milliseconds(2)) }
        #expect(opener.ready)
        #expect(dispatcher.submit(.finder(.paste), context: context))
        for _ in 0..<500 where output.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        #expect(output == [.command])
        #expect(opener.ready, "Paste must complete before the unrelated launch finishes")
        opener.finish()
        try await wait(dispatcher)
    }

    @Test func synchronousCopyRevokesACutStillWaitingForFinderFocus() async throws {
        let focus = DeferredClipboardFinderFocus()
        var output: [Modifiers] = []
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
            keyEmitter: { _, flags, _ in output.append(flags); return true },
            finderPasteboard: { board }, finderFocus: { _ in await focus.read() })
        dispatcher.update(context: context, enabled: true, finderEnabled: true)
        #expect(dispatcher.submit(.finder(.cut), context: context))
        for _ in 0..<500 { if await focus.ready { break }; try await Task.sleep(for: .milliseconds(2)) }
        #expect(await focus.ready)
        #expect(dispatcher.hasPendingFinderCut)
        dispatcher.observeNativeCopy()
        await focus.finish(.files)
        try await wait(dispatcher)
        #expect(output.isEmpty, "An older cut must not overwrite a later native copy")
        #expect(!dispatcher.hasPendingFinderCut)
        #expect(dispatcher.submit(.finder(.paste), context: context))
        try await wait(dispatcher)
        #expect(output == [.command])
    }

    @Test func acknowledgedFileCutMovesOnceAndLaterPasteCopiesNormally() async throws {
        var output: [(UInt16, Modifiers)] = []
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
            keyEmitter: { key, flags, _ in
                output.append((key, flags))
                if key == 8 {
                    board.declareTypes([.fileURL], owner: nil)
                    board.setString("file:///wmb-private-test-fixture", forType: .fileURL)
                }
                return true
            }, finderPasteboard: { board }, finderFocus: { _ in .files })
        dispatcher.update(context: context, enabled: true, finderEnabled: true)
        #expect(dispatcher.submit(.finder(.cut), context: context))
        try await wait(dispatcher)
        #expect(dispatcher.hasPendingFinderCut)
        #expect(dispatcher.submit(.finder(.paste), context: context))
        try await wait(dispatcher)
        #expect(!dispatcher.hasPendingFinderCut)
        #expect(dispatcher.submit(.finder(.paste), context: context))
        try await wait(dispatcher)
        #expect(output.map(\.0) == [8, 9, 9])
        #expect(output.map(\.1) == [.command, [.command, .option], .command])
    }

    @Test(arguments: [false, true])
    func failedOrCancelledCutDoesNotLeaveAPendingMove(cancelled: Bool) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var emitted = false
        let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
            keyEmitter: { _, _, _ in emitted = true; return false },
            finderPasteboard: { board }, finderFocus: { _ in .files })
        dispatcher.update(context: context, enabled: true, finderEnabled: true)
        #expect(dispatcher.submit(.finder(.cut), context: context))
        if cancelled { dispatcher.cancelPending(disable: true) }
        try await wait(dispatcher)
        #expect(emitted == !cancelled)
        #expect(!dispatcher.hasPendingFinderCut)
    }
}
