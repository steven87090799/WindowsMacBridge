import Foundation
import Testing
import Darwin
@testable import BridgePlatform

struct MappingJournalTests {
    @Test func durableJournalSurvivesIndependentProcessAndRejectsSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeJournal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let data = Data(#"{"bootID":"test","originals":{"1":[]}}"#.utf8)
        #expect(PrivateMappingJournal.write(data, to: url))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", "import json,sys; assert json.load(open(sys.argv[1]))['bootID']=='test'", url.path]
        try child.run(); child.waitUntilExit()
        #expect(child.terminationStatus == 0)
        #expect(PrivateMappingJournal.load(url) == data)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(PrivateMappingJournal.load(link) == nil)
        #expect(PrivateMappingJournal.remove(url))
    }
    @Test func invalidOrUnwritableParentFailsBeforeMappingCanBeSaved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeJournal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("file".utf8).write(to: root)
        #expect(!PrivateMappingJournal.write(Data("original".utf8), to: root.appendingPathComponent("journal")))
    }
}
