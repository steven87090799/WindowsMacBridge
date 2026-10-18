import Foundation
import Darwin
import BridgeCore

@main enum TextWorkerMain {
    static func main() {
        guard geteuid() != 0 else { exit(77) }
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--self-check"] {
            print("WindowsMacBridge OCR helper ready; no image read or Vision request started.")
            return
        }
        guard ScreenshotTextWorker.handle(arguments) else { exit(64) }
    }
}
