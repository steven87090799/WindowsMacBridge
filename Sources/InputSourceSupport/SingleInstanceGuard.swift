// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import AppKit
import Darwin
import Foundation

final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    private var lockFileDescriptor: Int32 = -1

    private init() {}

    func acquire() -> Bool {
        guard lockFileDescriptor < 0 else { return true }

        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local.WindowsMacBridge.instance.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            FileLogger.shared.log("Unable to open single-instance lock file; errno \(errno)")
            return false
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor
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
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
        }
    }
}
