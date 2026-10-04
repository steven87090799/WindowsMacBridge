import Darwin
import Foundation
import Testing
import HIDLifecycle

struct ExclusivePublishTests {
    private func sandbox() -> (root: URL, staged: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-publish-\(UUID().uuidString)").resolvingSymlinksInPath()
        let staged = root.appendingPathComponent("stage/WindowsMacBridge.app")
        try? FileManager.default.createDirectory(at: staged.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: staged.appendingPathComponent("Contents/marker").path, contents: Data("new".utf8))
        let applications = root.appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        return (root, staged, applications.appendingPathComponent("WindowsMacBridge.app"))
    }
    @Test func publishesAtTheExactPathWhenItIsFree() {
        let (root, staged, destination) = sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(ExclusivePublish.rename(staged.path, to: destination.path) == 0)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/marker").path))
    }
    @Test func directoryThatAppearedIsNeitherReplacedNorEntered() {
        let (root, staged, destination) = sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)   // empty dir: plain rename would replace it
        #expect(ExclusivePublish.rename(staged.path, to: destination.path) == EEXIST)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: destination.path))?.isEmpty == true)
    }
    @Test func symlinkOrFileAtTheDestinationIsNotFollowedOrOverwritten() {
        let (root, staged, destination) = sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let elsewhere = root.appendingPathComponent("elsewhere"); try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: destination, withDestinationURL: elsewhere)
        #expect(ExclusivePublish.rename(staged.path, to: destination.path) == EEXIST)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: elsewhere.path))?.isEmpty == true)
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: Data("foreign".utf8))
        #expect(ExclusivePublish.rename(staged.path, to: destination.path) == EEXIST)
        #expect((try? String(contentsOf: destination, encoding: .utf8)) == "foreign")
    }
    @Test func rejectsUnexpectedPathsAndLinkedSources() {
        let (root, staged, destination) = sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(ExclusivePublish.rename(staged.path, to: destination.deletingLastPathComponent().appendingPathComponent("Other.app").path) == EINVAL)
        #expect(ExclusivePublish.rename(staged.path, to: root.path + "/Applications/../Applications/WindowsMacBridge.app") == EINVAL)
        let link = root.appendingPathComponent("link.app"); try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: staged)
        #expect(ExclusivePublish.rename(link.path, to: destination.path) == ENOTDIR)
        // A symlinked parent directory is refused.
        let linkedParent = root.appendingPathComponent("LinkedApplications")
        try? FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: destination.deletingLastPathComponent())
        #expect(ExclusivePublish.rename(staged.path, to: linkedParent.appendingPathComponent("WindowsMacBridge.app").path) == ENOTDIR)
    }
}
