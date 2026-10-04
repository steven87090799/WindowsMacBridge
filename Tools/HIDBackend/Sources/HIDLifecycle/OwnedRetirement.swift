import Darwin

/// Moves an expected App into a private transaction directory without replacing
/// its destination. A writable source namespace cannot make identity-check and
/// rename atomic: validate the object actually moved before permitting cleanup.
public enum OwnedRetirement {
    public static func retire(_ source: String, to destination: String, identity: String) -> Int32 {
        retire(source, to: destination, identity: identity, afterValidation: {}, afterMove: {})
    }

    // Race hooks are internal; the installer CLI always uses the public entry.
    static func retire(_ source: String, to destination: String, identity: String,
                       afterValidation: () -> Void, afterMove: () -> Void) -> Int32 {
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let device = Int64(parts[0]), let inode = UInt64(parts[1]),
              source != destination, source.hasPrefix("/"), destination.hasPrefix("/"),
              !source.split(separator: "/").contains(".."), !destination.split(separator: "/").contains(".."),
              source.split(separator: "/").last.map(String.init) == ExclusivePublish.bundleName else { return EINVAL }
        for path in [source, destination] {
            let parent = String(path[..<path.lastIndex(of: "/")!])
            var info = stat()
            guard lstat(parent.isEmpty ? "/" : parent, &info) == 0,
                  info.st_mode & S_IFMT == S_IFDIR else { return ENOTDIR }
        }
        func matches(_ path: String) -> Bool {
            var info = stat()
            return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR &&
                Int64(info.st_dev) == device && UInt64(info.st_ino) == inode
        }
        // Pin the validated directory until retirement resolves. Its inode
        // cannot be recycled for a replacement in the validation/rename gap.
        let descriptor = open(source, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return ESTALE }
        defer { close(descriptor) }
        var original = stat()
        guard fstat(descriptor, &original) == 0, original.st_mode & S_IFMT == S_IFDIR,
              Int64(original.st_dev) == device, UInt64(original.st_ino) == inode,
              matches(source) else { return ESTALE }
        afterValidation()
        guard renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 else { return errno }
        afterMove()
        guard matches(destination) else {
            // We raced with a foreign replacement. Put that exact object back
            // only if the source path is still free. If occupied, leave it in the
            // private stage: the caller must retain the entire recovery snapshot.
            _ = renamex_np(destination, source, UInt32(RENAME_EXCL))
            return ESTALE
        }
        return 0
    }
}
