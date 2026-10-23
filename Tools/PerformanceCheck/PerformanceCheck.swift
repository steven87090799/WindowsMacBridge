import Foundation
import Darwin
import CoreGraphics
import CoreText
import ImageIO
import BridgeCore
import BridgePlatform

/// Offline measurements against generated inputs. No user keystrokes, windows,
/// screen capture, general pasteboard, native mappings or remote connections.
@main enum BridgePerformanceCheck {
    @MainActor static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "--modifier-cycles":
            let measurements = [false, true].flatMap { independent in
                (0..<3).map { _ in modifierCycles(independent: independent) }
            }
            try printJSON(["kind":"synthetic-modifier-cycles", "measurements":measurements])
        case "--routing-updates":
            let measurements = [0, 1, 16].map { sources in
                (0..<3).map { _ in routingUpdates(sources: sources) }
            }.flatMap { $0 }
            try printJSON(["kind":"synthetic-routing-update", "measurements":measurements])
        case "--preview":
            var configuration = ShortcutPreviewConfiguration()
            configuration.context = .init(processID: 10, bundleID: "com.apple.Terminal", mode: .terminal)
            let samples = ShortcutPreview.samples(windowsKey: .command)
            var count = 0
            let metrics = measure(iterations: 500) {
                for sample in samples {
                    if ShortcutPreview.evaluate(sample, configuration: configuration).decision != .suppress { count += 1 }
                }
            }
            try printJSON(["kind":"offline-preview", "evaluated_chords":count, "metrics":metrics])
        case "--ocr-roundtrip" where args.count == 2:
            let png = try fixture()
            let host = URL(fileURLWithPath: args[1])
            let executable = host.lastPathComponent == "WindowsMacBridge" ?
                host.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Helpers/\(ScreenshotTextBudget.workerExecutableName)") : host
            let recognizer = IsolatedScreenshotTextRecognizer(executable: executable)
            let before = footprint(), cpuBefore = cpuSeconds(), start = ProcessInfo.processInfo.systemUptime
            var results: [[String: Any]] = []
            for _ in 0..<3 {
                let workStart = ProcessInfo.processInfo.systemUptime
                let result = await recognizer.recognize(png: png)
                switch result {
                case .success(let text):
                    guard text.uppercased().contains("SCREEN TEXT 123") else { throw CocoaError(.coderInvalidValue) }
                    results.append(["seconds":ProcessInfo.processInfo.systemUptime - workStart,
                                    "parent_footprint_bytes":footprint(), "text_characters":text.count])
                case .failure(let failure): throw failure
                }
            }
            var children = rusage(); _ = getrusage(RUSAGE_CHILDREN, &children)
            try printJSON(["kind":"generated-ocr-roundtrip", "runs":results, "parent_before_bytes":before,
                "parent_after_bytes":footprint(), "parent_cpu_seconds":cpuSeconds() - cpuBefore,
                "wall_seconds":ProcessInfo.processInfo.systemUptime - start,
                "worker_max_rss_bytes":children.ru_maxrss])
        case "--write-fixture" where args.count == 2:
            try fixture().write(to: URL(fileURLWithPath: args[1]), options: .withoutOverwriting)
            try printJSON(["fixture":"generated SCREEN TEXT 123", "path":args[1]])
        default:
            print("Usage: BridgePerformanceCheck --modifier-cycles | --routing-updates | --preview | --ocr-roundtrip <App-executable> | --write-fixture <new-file>")
            exit(64)
        }
    }
    private static func modifierCycles(independent: Bool) -> [String: Any] {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: 10, bundleID: "synthetic.local", mode: .macOS),
            enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        let down = KeyboardEvent(.flagsChanged, keyCode: 59, modifiers: .control,
            modifierSide: .leftControl, modifierDown: true)
        let events = [down, down, KeyboardEvent(.down, keyCode: 8, modifiers: .control),
            KeyboardEvent(.up, keyCode: 8, modifiers: .control),
            KeyboardEvent(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false)]
        var result = measure(iterations: 20_000) {
            for event in events {
                if independent { _ = processor.processIndependentSource(event) }
                else { _ = processor.process(event) }
            }
        }
        precondition(processor.activePressCount == 0 && processor.modifiers.aggregate.isEmpty && processor.modifiers.synchronized)
        result["independent_flags"] = independent
        result["events_per_operation"] = events.count
        result["translated_chords"] = processor.translatedCount
        return result
    }
    private static func routingUpdates(sources: Int) -> [String: Any] {
        let producers = (0..<sources).map { i in
            RemoteProducer(processID: Int32(100 + i), identity: "synthetic-\(i)", session: 1, revision: 1,
                transport: .generic, confidence: .known, semantics: .windows, independentFlags: true)
        }
        let snapshot = InputRoutingSnapshot(producers: producers)
        var configuration = SourceTranslationConfiguration()
        configuration.context = .init(processID: 10, bundleID: "synthetic.local", mode: .macOS)
        configuration.enabled = true; configuration.layoutSupported = true
        var router = RemoteSourceRouter()
        router.update(snapshot, configuration: configuration)
        for producer in producers {
            let evidence = InputOriginEvidence(processID: producer.processID, stateID: -1)
            _ = router.process(.init(.flagsChanged, keyCode: 59, modifiers: .control, modifierSide: .leftControl, modifierDown: true), evidence: evidence)
            _ = router.process(.init(.down, keyCode: 8, modifiers: .control), evidence: evidence)
            _ = router.process(.init(.up, keyCode: 8, modifiers: .control), evidence: evidence)
            _ = router.process(.init(.flagsChanged, keyCode: 59, modifierSide: .leftControl, modifierDown: false), evidence: evidence)
        }
        var result = measure(iterations: 20_000) { router.update(snapshot, configuration: configuration) }
        result["sources"] = sources; result["primed_events"] = router.processedCount
        return result
    }
    private static func measure(iterations: Int, work: () -> Void) -> [String: Any] {
        var batches = [Double](); batches.reserveCapacity(iterations)
        for _ in 0..<100 { work() }
        let before = footprint(), startCPU = cpuSeconds(), start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations {
            let stamp = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<10 { work() }
            batches.append(Double(DispatchTime.now().uptimeNanoseconds - stamp) / 10_000)
        }
        let cpu = cpuSeconds() - startCPU, elapsed = ProcessInfo.processInfo.systemUptime - start
        batches.sort()
        return ["operations":iterations * 10, "wall_seconds":elapsed, "cpu_seconds":cpu,
            "p50_batch_mean_microseconds":batches[iterations / 2],
            "p95_batch_mean_microseconds":batches[iterations * 95 / 100],
            "p99_batch_mean_microseconds":batches[iterations * 99 / 100],
            "footprint_before_bytes":before, "footprint_after_bytes":footprint()]
    }
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    private static func cpuSeconds() -> Double {
        var value = rusage(); _ = getrusage(RUSAGE_SELF, &value)
        return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
    }
    private static func fixture() throws -> Data {
        guard let context = CGContext(data: nil, width: 900, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScreenshotFailure.decodeFailure }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 900, height: 180))
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 58, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
        context.textPosition = CGPoint(x: 30, y: 65)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "SCREEN TEXT 123", attributes: attributes)), context)
        guard let image = context.makeImage() else { throw ScreenshotFailure.encodeFailure }
        let bytes = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else { throw ScreenshotFailure.encodeFailure }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw ScreenshotFailure.encodeFailure }
        return bytes as Data
    }
    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted,.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
