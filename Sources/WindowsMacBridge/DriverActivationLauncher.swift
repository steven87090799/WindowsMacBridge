import Foundation
import Security

/// The official Manager's `activate` entry is a command-line program, not a
/// Cocoa application accepting LaunchServices reopen events. At most one child
/// waits for approval; stop only our child, never the shared driver service.
@MainActor final class DriverActivationLauncher {
    private var child: Process?
    private var timeout: DispatchWorkItem?
    func start(completion: @escaping @MainActor (Int32) -> Void) throws {
        guard child == nil else { return }
        let bundle = URL(fileURLWithPath: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app")
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let expected = "anchor apple generic and identifier \"org.pqrs.Karabiner-VirtualHIDDevice-Manager\" and certificate leaf[subject.OU] = \"G43BCU2T37\"" as CFString
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(expected, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw NSError(domain: "WindowsMacBridge.Driver", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "鍵盤驅動程式尚未正確安裝，請關閉並重新開啟 App 完成安裝。"])
        }
        let process = Process()
        process.executableURL = bundle.appendingPathComponent("Contents/MacOS/Karabiner-VirtualHIDDevice-Manager")
        process.arguments = ["activate"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.child === process else { return }
                self.timeout?.cancel(); self.timeout = nil; self.child = nil
                completion(process.terminationStatus)
            }
        }
        try process.run(); child = process
        let timeout = DispatchWorkItem { [weak self, weak process] in
            MainActor.assumeIsolated { if self?.child === process, process?.isRunning == true { process?.terminate() } }
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
    }
    func stop() {
        timeout?.cancel(); timeout = nil
        child?.terminationHandler = nil
        if child?.isRunning == true { child?.terminate() }
        child = nil
    }
}
