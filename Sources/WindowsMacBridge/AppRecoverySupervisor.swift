import AppKit
import BridgeCore
import Darwin

/// A private pipe, rather than a recurring heartbeat, detects unexpected exit.
/// The small child waits in read(2); normal termination sends Q before exit.
@MainActor final class AppRecoverySupervisor {
    private let process = Process()
    private let input = Pipe()
    private var disarmed = false
    private var noticePresented = false
    private(set) var isArmed = false
    private(set) var startupIssue: String?
    var onStatusChange: (() -> Void)?
    let launch: RecoveryLaunchContext

    init() {
        launch = RecoveryLaunchContext(arguments: CommandLine.arguments,
                                       nowMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000))
    }

    func start() {
        guard Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/WindowsMacBridge.app" else { return }
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/WindowsMacBridgeRecovery")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/WindowsMacBridge/Recovery", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw CocoaError(.fileWriteNoPermission) }
            process.executableURL = helper
            process.arguments = [Bundle.main.bundleURL.path, directory.path, String(launch.attempt), String(launch.windowMilliseconds)]
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.disarmed else { return }
                    self.isArmed = false
                    self.startupIssue = "自動恢復程序已停止。WindowsMacBridge 仍在執行，但下次異常停止時可能無法自動重開；請正常結束並重新開啟 App。"
                    self.noticePresented = false
                    self.onStatusChange?()
                    self.showStartupNotice()
                }
            }
            // Only the monitor's read endpoint is inherited by the child.
            guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try process.run()
            isArmed = true
            try input.fileHandleForReading.close()
            if let token = launch.token {
                try Data("ready".utf8).write(to: directory.appendingPathComponent("ready-" + token), options: .atomic)
            }
        } catch {
            isArmed = false
            startupIssue = "自動恢復程序未能啟動：\(error.localizedDescription)。本次異常停止時可能無法自動重開。"
        }
    }

    func disarm() {
        guard !disarmed else { return }
        disarmed = true
        isArmed = false
        try? input.fileHandleForWriting.write(contentsOf: Data("Q".utf8))
        try? input.fileHandleForWriting.close()
    }

    func showStartupNotice() {
        guard !noticePresented, startupIssue != nil || launch.isRecovery else { return }
        noticePresented = true
        let alert = NSAlert()
        if let startupIssue {
            alert.messageText = "WindowsMacBridge 自動恢復尚未就緒"
            alert.informativeText = startupIssue
            alert.alertStyle = .warning
        } else {
            alert.messageText = "WindowsMacBridge 已自動重新啟動"
            alert.informativeText = "剛剛偵測到程式非預期停止，已自動重新開啟（本輪第 \(launch.attempt) 次）。目前功能是否可用，以權限頁的「運作中」狀態為準。五分鐘內最多恢復三次，持續異常時會停止嘗試並通知你。"
            alert.alertStyle = .informational
        }
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
