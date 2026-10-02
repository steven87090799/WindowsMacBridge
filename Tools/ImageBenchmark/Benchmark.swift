import Foundation
import BridgePlatform
import AppKit
import BridgeCore

/// Opt-in, isolated process. Optional clipboard measurement uses a disposable
/// named pasteboard, never the user's general clipboard or screenshot contents.
@main enum BridgeImageBenchmark {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--private-clipboard") else {
            print("Usage: BridgeImageBenchmark <generated-fixture-path|--baseline> [--private-clipboard]"); exit(64)
        }
        let path = arguments[0]
        if path == "--baseline" { print("baseline; no image processing"); return }
        let start = ProcessInfo.processInfo.systemUptime
        let result = ScreenshotImagePreparation.prepareResult(at: URL(fileURLWithPath: path))
        switch result {
        case .success(let payload):
            if arguments.count == 2 {
                let board = NSPasteboard(name: .init("BridgeImageBenchmark-\(UUID().uuidString)"))
                defer { board.releaseGlobally() }
                guard ScreenshotClipboard.write(payload, to: board) == .success,
                      let image = NSImage(pasteboard: board),
                      let decoded = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      ImageMemoryBudget.allows(width: decoded.width, height: decoded.height, bytesPerPixel: 4),
                      let bitmap = CGContext(data: nil, width: decoded.width, height: decoded.height,
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(3) }
                // Obtaining a CGImage can remain lazy. Actually draw the pasted
                // image so this measurement includes destination raster memory.
                bitmap.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
                print("privateClipboard rendered=\(decoded.width)x\(decoded.height)")
            }
            print("success pngBytes=\(payload.encodedByteCount) elapsedSeconds=\(ProcessInfo.processInfo.systemUptime - start)")
        case .failure(let failure): print("failure=\(failure.rawValue)"); exit(2)
        }
    }
}
