import AppKit
import Testing
import BridgeCore
@testable import BridgePlatform

@MainActor struct RunningApplicationSnapshotTests {
    private final class Application: RunningApplicationInfo {
        var pid: Int32
        var isTerminated = false
        var bundleIdentifier: String?
        var executableURL: URL? = URL(fileURLWithPath: "/Applications/Test.app/Contents/MacOS/Test")
        var name: String = "Test"
        var terminateWhileReadingMetadata = false
        var invalidateAfterPIDRead = false
        var pidReads = 0
        var metadataReads = 0

        init(_ pid: Int32, bundle: String = "com.apple.finder") {
            self.pid = pid; bundleIdentifier = bundle
        }
        var processIdentifier: Int32 {
            pidReads += 1
            let value = pid
            if invalidateAfterPIDRead { pid = -1 }
            return value
        }
        var localizedName: String? {
            metadataReads += 1
            if terminateWhileReadingMetadata { isTerminated = true }
            return name
        }
    }

    @Test func reportedDuplicateMinusOneEntriesDoNotCrashOrDiscardLiveRecipients() throws {
        let registry = try ApplicationRegistry()
        let result = RunningApplicationSnapshot.collect([
            Application(-1), Application(42), Application(-1), Application(73, bundle: "com.apple.Terminal")
        ], registry: registry, overrides: [:])
        #expect(Set(result.keys) == [42, 73])
        #expect(result[42]?.mode == .macOS && result[73]?.mode == .terminal)
        let recipient = DestinationSemanticPolicy.context(target: 73, foreground: .init(processID: 42), recipients: result)
        #expect(recipient?.bundleID == "com.apple.Terminal" && recipient?.mode == .terminal)
    }

    @Test func nonpositiveAndTerminatedProcessesAreSkippedBeforeReadingMetadata() {
        let applications = [Application(-1), Application(-1), Application(0), Application(-23), Application(42)]
        applications.last?.isTerminated = true
        let result = RunningApplicationSnapshot.collect(applications, registry: nil, overrides: [:])
        #expect(result.isEmpty)
        #expect(applications.allSatisfy { $0.metadataReads == 0 })
    }

    @Test func duplicateValidPIDKeepsLatestContextAndRules() throws {
        let old = Application(42), updated = Application(42, bundle: "com.apple.Terminal")
        updated.name = "Terminal"
        let result = RunningApplicationSnapshot.collect([old, updated], registry: try ApplicationRegistry(),
                                                       overrides: ["com.apple.Terminal": .disabled])
        #expect(result.count == 1 && result[42]?.displayName == "Terminal")
        #expect(result[42]?.bundleID == "com.apple.Terminal" && result[42]?.mode == .disabled)
    }

    @Test func terminationDuringMetadataReadDoesNotPublishADeadRecipient() {
        let application = Application(42)
        application.terminateWhileReadingMetadata = true
        #expect(RunningApplicationSnapshot.collect([application], registry: nil, overrides: [:]).isEmpty)
    }

    @Test func capturedPIDIsUsedForBothDictionaryKeyAndContext() {
        let application = Application(42)
        application.invalidateAfterPIDRead = true
        let result = RunningApplicationSnapshot.collect([application], registry: nil, overrides: [:])
        #expect(application.pidReads == 1)
        #expect(result[42]?.processID == 42 && result[-1] == nil)
    }

    @Test func successiveLifecycleSnapshotsRemoveStaleRecipients() {
        let application = Application(42)
        var result = RunningApplicationSnapshot.collect([application], registry: nil, overrides: [:])
        #expect(result[42] != nil)
        application.isTerminated = true
        result = RunningApplicationSnapshot.collect([application, Application(-1), Application(-1)], registry: nil, overrides: [:])
        #expect(result.isEmpty)
        #expect(RunningApplicationSnapshot.collect([Application](), registry: nil, overrides: [:]).isEmpty)
    }

    @Test func missingRegistryKeepsTranslationDisabled() {
        let result = RunningApplicationSnapshot.collect([Application(42)], registry: nil, overrides: [:])
        #expect(result[42]?.mode == .disabled && result[42]?.isBrowser == false)
    }

    @Test func realAppKitAdapterHandlesCurrentProcess() throws {
        let application = NSRunningApplication.current
        let pid = application.processIdentifier
        let result = RunningApplicationSnapshot.contexts(for: [application, application], registry: try ApplicationRegistry(), overrides: [:])
        // A command-line test process may itself be a PID-less AppKit entry.
        if pid <= 0 || application.isTerminated {
            #expect(result.isEmpty)
        } else {
            let context = try #require(result[pid])
            #expect(result.count == 1 && context.processID == pid)
            #expect(context.executablePath == application.executableURL?.path)
        }
    }
}
