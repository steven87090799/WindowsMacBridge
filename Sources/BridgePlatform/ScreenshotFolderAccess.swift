import Foundation
import Darwin

public enum ScreenshotFolderAccess {
    public static func currentDirectory(fileManager: FileManager = .default) -> URL {
        let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let directory = location.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        } ?? fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        return directory.resolvingSymlinksInPath().standardizedFileURL
    }

    /// A successful native directory read proves this process can read it.
    /// Unix access()/isReadableFile alone cannot prove a TCC grant. Read at most
    /// one directory entry, without allocating a file list or opening images.
    public static func canRead(_ directory: URL) -> Bool {
        guard directory.isFileURL, let handle = opendir(directory.path) else { return false }
        defer { closedir(handle) }
        errno = 0
        _ = readdir(handle)
        return errno == 0
    }
}
