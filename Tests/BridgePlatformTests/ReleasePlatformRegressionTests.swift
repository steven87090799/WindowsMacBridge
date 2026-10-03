import AppKit
import Testing
import BridgeCore
@testable import BridgePlatform

struct ReleasePlatformRegressionTests {
    @Test func finderDeleteUsesTextDeletionForTextAndUnknownFocus() {
        #expect(FinderActionPolicy.deleteOutput(focus: .files).keyCode == 51)
        #expect(FinderActionPolicy.deleteOutput(focus: .files).modifiers == .command)
        for focus: FinderFocus in [.text, .unknown, .folder] {
            let output = FinderActionPolicy.deleteOutput(focus: focus)
            #expect(output.keyCode == 117 && output.modifiers.isEmpty)
        }
    }
    @Test func armedCutMovesOnlyOnPositiveFileViewEvidence() {
        // An empty destination folder still moves; an AX failure or text field pastes.
        #expect(FinderActionPolicy.allowsMove(focus: .files) && FinderActionPolicy.allowsMove(focus: .folder))
        #expect(!FinderActionPolicy.allowsMove(focus: .unknown) && !FinderActionPolicy.allowsMove(focus: .text))
        #expect(FinderActionPolicy.inFileView(.folder) && !FinderActionPolicy.inFileView(.unknown))
    }
    @Test func filenameAndSidebarAreNotInferredAsFileSelectionFromRoleAlone() {
        #expect(FinderFocusReader.classify(role: kAXTextFieldRole, fileSelection: true, sidebar: false) == .text)
        #expect(FinderFocusReader.classify(role: kAXOutlineRole, fileSelection: false, sidebar: false) == .unknown)
        #expect(FinderFocusReader.classify(role: kAXOutlineRole, fileSelection: true, sidebar: true) == .unknown)
        #expect(FinderFocusReader.classify(role: kAXTableRole, fileSelection: true, sidebar: false) == .files)
    }
    @Test func windowsScreenshotVariantsPairAndRespectPrintScreenPreference() {
        for selected in WindowsKeyModifier.allCases {
            for behavior in PrintScreenBehavior.allCases {
                var shortcut = ScreenshotShortcut(windowsKeyModifier: selected)
                shortcut.printScreenBehavior = behavior
                for (key, flags, kind): (UInt16, Modifiers, ScreenshotKind) in [
                    (1, [selected.flag, .shift], .region),
                    (105, [], behavior == .snipping ? .region : .fullScreen),
                    (105, selected.altFlag, .activeWindow),
                    (105, selected.flag, .fullScreenSave)
                ] {
                    let decision = shortcut.handle(keyCode: key, isDown: true, isRepeat: false,
                        command: flags.contains(.command), shift: flags.contains(.shift),
                        option: flags.contains(.option), control: flags.contains(.control))
                    #expect(decision == .capture && shortcut.captureKind == kind)
                    #expect(shortcut.handle(keyCode: key, isDown: false, isRepeat: false,
                        command: false, shift: false, option: false, control: false) == .suppress)
                }
            }
        }
    }
    @MainActor @Test func failedMailboxSubmissionCanPassThroughBalancedActionPress() {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: .max, bundleID: "com.apple.finder", mode: .macOS),
                            enabled: true, layoutSupported: true, finderEnabled: true)
        processor.reconcileNeutralHardware()
        #expect(processor.process(.init(.down, keyCode: 117)) == .action(.finder(.trash), ruleID: "finder.delete"))
        processor.rejectAction(keyCode: 117)
        #expect(processor.process(.init(.up, keyCode: 117)) == .passThrough)
    }
}
