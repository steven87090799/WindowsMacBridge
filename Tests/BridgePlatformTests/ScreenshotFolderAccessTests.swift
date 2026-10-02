import Foundation
import Testing
@testable import BridgePlatform

@Suite struct ScreenshotFolderAccessTests {
    @Test func onlyAnActuallyReadableDirectoryPasses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(ScreenshotFolderAccess.canRead(directory))
        #expect(!ScreenshotFolderAccess.canRead(directory.appendingPathComponent("missing")))
        let file = directory.appendingPathComponent("file")
        try Data().write(to: file)
        #expect(!ScreenshotFolderAccess.canRead(file))
        #expect(!ScreenshotFolderAccess.canRead(URL(string: "https://example.com")!))
    }
}
