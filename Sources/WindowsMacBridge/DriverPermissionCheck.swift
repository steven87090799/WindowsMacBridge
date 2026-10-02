import Foundation
import BridgeCore

enum DriverPermissionCheck {
    struct Result: Sendable { let granted: Bool; let registered: Bool }
    static func read() async -> Result? {
        await Task.detached(priority: .utility) { () -> Result? in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
            process.arguments = ["list"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            try? output.fileHandleForWriting.close()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
            defer { timeout.cancel(); try? output.fileHandleForReading.close() }
            var data = Data()
            do {
                while data.count <= 16_384 {
                    let chunk = try output.fileHandleForReading.read(upToCount: min(4096, 16_385 - data.count)) ?? Data()
                    if chunk.isEmpty { break }
                    data.append(chunk)
                }
            } catch { if process.isRunning { process.terminate() }; return nil }
            if data.count > 16_384, process.isRunning { process.terminate() }
            process.waitUntilExit()
            guard process.terminationStatus == 0, data.count <= 16_384,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return Result(granted: DriverApproval.isEnabled(in: text), registered: DriverApproval.isRegistered(in: text))
        }.value
    }
}
