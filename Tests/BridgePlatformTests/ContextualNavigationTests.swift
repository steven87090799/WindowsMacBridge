import ApplicationServices
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor private final class DeferredTextFocus {
    var continuation: CheckedContinuation<Bool, Never>?
    func read() async -> Bool { await withCheckedContinuation { continuation = $0 } }
}

@MainActor struct ContextualNavigationTests {
    private let context = ApplicationContext(processID: 100, bundleID: "com.google.Chrome", mode: .macOS, isBrowser: true)

    @Test func textFocusUsesLineNavigationAndPageFocusKeepsNativeHomeEnd() async {
        for text in [false, true] {
            for action in [TextNavigationAction.home, .end, .selectHome, .selectEnd, .paragraphUp] {
                var output: [Shortcut] = []
                let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
                    keyEmitter: { key, flags, _ in output.append(.init(keyCode: key, modifiers: flags)); return true },
                    textFocus: { _ in text })
                dispatcher.update(context: context, enabled: true)
                #expect(dispatcher.submit(.textNavigation(action), context: context))
                for _ in 0..<100 where dispatcher.hasPendingWork { await Task.yield() }
                let expected = action.output(textFocused: text).map { [$0] } ?? []
                #expect(output == expected)
                // No page-focused action ever emits the browser's Command+Left/Right history chord.
                if !text { #expect(!output.contains { $0.modifiers == .command }) }
            }
        }
    }
    @Test func pauseOrSourceRevocationDuringFocusReadCannotEmitDelayedNavigation() async {
        for revokeSource in [false, true] {
            let focus = DeferredTextFocus()
            let gate = SourceWorkGate()
            var output = 0
            let dispatcher = ShortcutActionDispatcher(marker: 1, authorization: { _ in true }, clock: { 0 },
                keyEmitter: { _, _, _ in output += 1; return true }, textFocus: { _ in await focus.read() })
            dispatcher.update(context: context, enabled: true)
            #expect(dispatcher.submit(.textNavigation(.home), context: context,
                source: .init(origin: gate, frame: .init())))
            for _ in 0..<100 where focus.continuation == nil { await Task.yield() }
            guard let continuation = focus.continuation else { Issue.record("Focus reader did not start"); continue }
            if revokeSource { gate.invalidate() } else { dispatcher.cancelPending(disable: true) }
            continuation.resume(returning: true)
            for _ in 0..<100 where dispatcher.hasPendingWork { await Task.yield() }
            #expect(output == 0)
        }
    }
    @Test func onlyTextRolesCountAsPositiveFocusEvidence() {
        for role in [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole] {
            #expect(TextNavigationFocusReader.isTextRole(role))
        }
        for role in ["AXWebArea", kAXButtonRole, kAXTableRole, "", "AXUnknown"] {
            #expect(!TextNavigationFocusReader.isTextRole(role))
        }
    }
}
