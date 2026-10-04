import Darwin

/// Atomic, conditioned publish of a staged bundle at an exact path.
/// `mv` decides from a separate stat whether the target is a directory and then
/// moves *into* it, and a check-then-move leaves a race. rename(2) with
/// RENAME_EXCL is one operation: it fails with EEXIST when anything (file,
/// directory or symlink) exists at the destination and never follows a
/// destination symlink. Cross-volume moves fail (EXDEV) instead of copying.
public enum ExclusivePublish {
    public static let bundleName = "WindowsMacBridge.app"
    /// Returns 0 or an errno value.
    public static func rename(_ source: String, to destination: String) -> Int32 {
        guard source.hasPrefix("/"), destination.hasPrefix("/"),
              !source.split(separator: "/").contains(".."), !destination.split(separator: "/").contains(".."),
              destination.split(separator: "/").last.map(String.init) == bundleName else { return EINVAL }
        var info = stat()
        // The source must be a real directory (the staged bundle), not a link.
        guard lstat(source, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return ENOTDIR }
        // The destination's parent must be a real directory, not a symlink.
        let parent = String(destination[..<destination.lastIndex(of: "/")!])
        guard lstat(parent.isEmpty ? "/" : parent, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return ENOTDIR }
        return renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
    }
}
