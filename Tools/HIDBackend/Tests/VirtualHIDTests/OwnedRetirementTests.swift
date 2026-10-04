import Darwin
import Foundation
import Testing
@testable import HIDLifecycle

struct OwnedRetirementTests {
    private func sandbox() throws -> (URL, URL, URL, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-retire-\(UUID().uuidString)").resolvingSymlinksInPath()
        let source = root.appendingPathComponent("Applications/WindowsMacBridge.app")
        let target = root.appendingPathComponent("stage/retired.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("owned".utf8).write(to: source.appendingPathComponent("owned"))
        var info = stat(); #expect(lstat(source.path, &info) == 0)
        return (root, source, target, "\(info.st_dev):\(info.st_ino)")
    }
    @Test func matchingObjectIsRetiredWithoutOverwritingAnything() throws {
        let (root, source, target, identity) = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(OwnedRetirement.retire(source.path, to: target.path, identity: identity) == 0)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: target.appendingPathComponent("owned")) == Data("owned".utf8))
    }
    @Test func replacementBeforeValidationIsLeftAtTheSource() throws {
        let (root, source, target, identity) = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("original.app"))
        try Data("foreign".utf8).write(to: source)
        #expect(OwnedRetirement.retire(source.path, to: target.path, identity: identity) == ESTALE)
        #expect(try Data(contentsOf: source) == Data("foreign".utf8))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    @Test func replacementInsideRenameIsRestoredForDirectoriesFilesAndLinks() throws {
        for kind in 0..<3 {
            let (root, source, target, identity) = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
            let elsewhere = root.appendingPathComponent("elsewhere")
            try Data("unrelated".utf8).write(to: elsewhere)
            let result = OwnedRetirement.retire(source.path, to: target.path, identity: identity, afterValidation: {
                try! FileManager.default.moveItem(at: source, to: root.appendingPathComponent("original.app"))
                if kind == 0 {
                    try! FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
                    try! Data("foreign".utf8).write(to: source.appendingPathComponent("foreign"))
                } else if kind == 1 { try! Data("foreign".utf8).write(to: source) }
                else { try! FileManager.default.createSymbolicLink(at: source, withDestinationURL: elsewhere) }
            }, afterMove: {})
            #expect(result == ESTALE)
            #expect(!FileManager.default.fileExists(atPath: target.path))
            if kind == 0 { #expect(try Data(contentsOf: source.appendingPathComponent("foreign")) == Data("foreign".utf8)) }
            else if kind == 1 { #expect(try Data(contentsOf: source) == Data("foreign".utf8)) }
            else { #expect(try FileManager.default.destinationOfSymbolicLink(atPath: source.path) == elsewhere.path) }
            #expect(try Data(contentsOf: elsewhere) == Data("unrelated".utf8))
        }
    }
    @Test func failedPutBackPreservesTheQuarantineAndTheNewSourceObject() throws {
        let (root, source, target, identity) = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let result = OwnedRetirement.retire(source.path, to: target.path, identity: identity, afterValidation: {
            try! FileManager.default.moveItem(at: source, to: root.appendingPathComponent("original.app"))
            try! Data("foreign".utf8).write(to: source)
        }, afterMove: { try! Data("blocker".utf8).write(to: source) })
        #expect(result == ESTALE)
        #expect(try Data(contentsOf: target) == Data("foreign".utf8))
        #expect(try Data(contentsOf: source) == Data("blocker".utf8))
    }
    @Test func occupiedQuarantineIsNotReplaced() throws {
        let (root, source, target, identity) = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("foreign".utf8).write(to: target)
        #expect(OwnedRetirement.retire(source.path, to: target.path, identity: identity) == EEXIST)
        #expect(try Data(contentsOf: target) == Data("foreign".utf8))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("owned").path))
    }
    @Test func malformedIdentityAndUnexpectedPathsAreRejected() throws {
        let (root, source, target, _) = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(OwnedRetirement.retire(source.path, to: target.path, identity: "not-an-identity") == EINVAL)
        #expect(OwnedRetirement.retire(root.path + "/Applications/../Applications/WindowsMacBridge.app", to: target.path, identity: "1:1") == EINVAL)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("owned").path))
    }
}
