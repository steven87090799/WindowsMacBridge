import Foundation
import Darwin

/// Atomic, private and synced before UserKeyMapping mutation. No UserDefaults readback is used as durability proof.
enum PrivateMappingJournal {
    static func load(_ url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              info.st_size >= 0, info.st_size <= 64 * 1024,
              let data = try? file.read(upToCount: 64 * 1024 + 1), data.count <= 64 * 1024 else { return nil }
        return data
    }
    static func write(_ data: Data, to url: URL) -> Bool {
        guard data.count <= 64 * 1024 else { return false }
        let directory = url.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700]) }
        catch { return false }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_mode & 0o022 == 0 else { return false }
        let temporary = directory.appendingPathComponent(".fn-control-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor); unlink(temporary.path) }
        let written = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }; offset += count
            }
            return true
        }
        guard written, fsync(descriptor) == 0 else { return false }
        if fcntl(descriptor, F_FULLFSYNC) != 0 && errno != ENOTSUP && errno != EINVAL { return false }
        guard rename(temporary.path, url.path) == 0 else { return false }
        return syncDirectory(directory)
    }
    static func remove(_ url: URL) -> Bool {
        if unlink(url.path) != 0 { return errno == ENOENT }
        return syncDirectory(url.deletingLastPathComponent())
    }
    private static func syncDirectory(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return fsync(descriptor) == 0
    }
}
