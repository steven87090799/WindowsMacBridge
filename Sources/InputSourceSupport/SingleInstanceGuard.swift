// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import AppKit
import Darwin
import Foundation

final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    private var lockFileDescriptor: Int32 = -1
    private var legacyLockFileDescriptor: Int32 = -1

    private init() {}

    /// Exclusive, non-inherited lock on a regular file (never a symlink).
    private static func lock(_ url: URL) -> Int32? {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); return -1 }
        return descriptor
    }

    func acquire() -> Bool {
        guard lockFileDescriptor < 0 else { return true }

        // macOS purges unaccessed temporary-directory items; a weeks-long instance
        // could lose its lock file there and admit a second instance (two taps).
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let directory = support.appendingPathComponent("WindowsMacBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard let descriptor = Self.lock(directory.appendingPathComponent("instance.lock")) else {
            FileLogger.shared.log("Unable to open single-instance lock file; errno \(errno)")
            return false
        }
        guard descriptor >= 0 else { return false }
        // An older build still running holds the previous temporary lock.
        let legacy = Self.lock(FileManager.default.temporaryDirectory.appendingPathComponent("local.WindowsMacBridge.instance.lock"))
        if legacy == -1 { close(descriptor); return false }

        lockFileDescriptor = descriptor
        legacyLockFileDescriptor = legacy ?? -1
        return true
    }

    func activateExistingInstanceIfPossible() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier

        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID })?
            .activate(options: [])
    }

    deinit {
        for descriptor in [lockFileDescriptor, legacyLockFileDescriptor] where descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }
}
