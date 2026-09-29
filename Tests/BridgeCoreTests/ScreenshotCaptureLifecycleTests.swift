import Testing
import BridgeCore

struct ScreenshotCaptureLifecycleTests {
    @Test func capturesAreSingleFlightAndCompletionsCannotClearNewerWork() throws {
        var state = ScreenshotCaptureLifecycle()
        let disabled = state.begin()
        #expect(disabled == nil)
        state.configure(enabled: true)
        let firstRequest = state.begin()
        let first = try #require(firstRequest)
        let overlapping = state.begin()
        #expect(overlapping == nil)
        let firstCompletion = state.complete(first)
        #expect(firstCompletion)
        let secondRequest = state.begin()
        let second = try #require(secondRequest)
        let duplicate = state.complete(first)
        #expect(!duplicate)
        #expect(state.isCurrent(second))
        let secondCompletion = state.complete(second)
        #expect(secondCompletion)
    }
    @Test func disableAndReenableNeverResurrectAnOldClipboardWrite() throws {
        var state = ScreenshotCaptureLifecycle()
        state.configure(enabled: true)
        let request = state.begin()
        let token = try #require(request)
        state.configure(enabled: false)
        state.configure(enabled: true)
        #expect(!state.isCurrent(token))
        let overlapping = state.begin()
        #expect(overlapping == nil)
        let stale = state.complete(token)
        #expect(!stale)
        let nextRequest = state.begin()
        let next = try #require(nextRequest)
        let completed = state.complete(next)
        #expect(completed)
    }
    @Test func shutdownCancelsCompletionButRepeatedEnabledConfigurationDoesNot() throws {
        var state = ScreenshotCaptureLifecycle()
        state.configure(enabled: true)
        let request = state.begin()
        let token = try #require(request)
        state.configure(enabled: true)
        #expect(state.isCurrent(token))
        state.configure(enabled: false)
        let stoppedCompletion = state.complete(token)
        #expect(!stoppedCompletion)
        let disabled = state.begin()
        #expect(disabled == nil)
    }
}
