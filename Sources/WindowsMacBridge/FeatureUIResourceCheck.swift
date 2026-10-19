import AppKit
import SwiftUI
import Darwin
import MachO

/// Explicit generated-content lifecycle probe. Never starts BridgeController,
/// input, capture, OCR, permissions, clipboard access or visible windows.
@MainActor enum FeatureUIResourceCheck {
    private final class WeakObject {
        let kind: String
        weak var value: AnyObject?
        init(_ value: AnyObject, kind: String) { self.value = value; self.kind = kind }
    }

    static func handle(_ arguments: [String]) -> Bool {
        guard arguments.first == "--ui-resource-check" else { return false }
        guard arguments.count == 2 else { exit(64) }
        let destination = URL(fileURLWithPath: arguments[1])
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            NSApplication.shared.setActivationPolicy(.prohibited)
            var observations = [[String: Any]]()
            var owners = [WeakObject]()
            drain(seconds: 2)
            observations.append(snapshot("appkit-no-window"))
            // Warm up framework caches before looking for growth across batches.
            exerciseSettings(count: 3, owners: &owners)
            exercisePanels(count: 3, owners: &owners)
            drain(seconds: 2)
            observations.append(snapshot("warmed-closed"))
            let beforeIdle = cpuSeconds(), idleStart = ProcessInfo.processInfo.systemUptime
            drain(seconds: 30)
            let closedCPU = cpuSeconds() - beforeIdle
            let closedWall = ProcessInfo.processInfo.systemUptime - idleStart
            observations.append(snapshot("warmed-closed-idle"))
            for batch in 1...3 {
                exerciseSettings(count: 10, owners: &owners)
                exercisePanels(count: 10, owners: &owners)
                drain(seconds: 2)
                observations.append(snapshot("closed-batch-\(batch)"))
            }
            drain(seconds: 5)
            observations.append(snapshot("final-closed"))
            let retained = owners.filter { $0.value != nil }.map(\.kind)
            let result: [String: Any] = [
                "scope": "generated-offscreen-UI-only-no-input-engine-no-GPU-measurement",
                "settings_cycles": 33, "panel_cycles": 33,
                "weak_objects_checked": owners.count, "retained_objects": retained,
                "closed_idle_wall_seconds": closedWall, "closed_idle_cpu_seconds": closedCPU,
                "closed_idle_single_core_cpu_percent": closedCPU / closedWall * 100,
                "observations": observations
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination, options: .withoutOverwriting)
            print("UI resource check: \(owners.count) weak owners, \(retained.count) retained; \(destination.path)")
            if !retained.isEmpty { exit(1) }
        } catch { print("UI resource check failed: \(error)"); exit(1) }
        return true
    }

    private static func exerciseSettings(count: Int, owners: inout [WeakObject]) {
        for _ in 0..<count {
            autoreleasepool {
                let view = GlassSettingsChrome(selection: .constant(.general), advanced: true,
                    isOperating: true, status: "Generated resource fixture", version: "fixture") {
                    Form {
                        Section("Generated settings") {
                            Toggle("Enabled", isOn: .constant(true))
                            Text("No live controller or user data")
                            Button("Generated action") {}.bridgeGlassButton()
                        }
                    }.formStyle(.grouped).scrollContentBackground(.hidden)
                }
                let window = SettingsWindowFactory.make(content: view)
                owners.append(WeakObject(window, kind: "settings-window"))
                if let host = window.contentViewController { owners.append(WeakObject(host, kind: "hosting-controller")) }
                if let content = window.contentView { owners.append(WeakObject(content, kind: "hosting-view")) }
                window.contentView?.layoutSubtreeIfNeeded()
                SettingsWindowFactory.releaseContent(of: window)
                window.close()
            }
            drain(seconds: 0.05)
        }
    }

    private static func exercisePanels(count: Int, owners: inout [WeakObject]) {
        for _ in 0..<count {
            autoreleasepool {
                let image = NSImage(size: NSSize(width: 720, height: 420), flipped: false) { rect in
                    NSColor.systemBlue.setFill(); rect.fill(); return true
                }
                let content = ScreenshotThumbnailView(image: image, target: nil, openAction: nil, closeAction: nil)
                let panel = NSPanel(contentRect: content.bounds, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.contentView = content
                owners.append(WeakObject(panel, kind: "panel"))
                if let glass = content.subviews.first { owners.append(WeakObject(glass, kind: "glass-view")) }
                owners.append(WeakObject(content, kind: "panel-content"))
                panel.contentView?.layoutSubtreeIfNeeded()
                panel.contentView = nil
                panel.close()
            }
            drain(seconds: 0.05)
        }
    }

    private static func drain(seconds: TimeInterval) {
        autoreleasepool { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
    }

    private static func snapshot(_ phase: String) -> [String: Any] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let frameworks = (0..<_dyld_image_count()).compactMap { index -> String? in
            guard let path = _dyld_get_image_name(index) else { return nil }
            let name = String(cString: path)
            return ["/Vision.framework/", "/VisionKit.framework/", "/CoreML.framework/"].contains { name.contains($0) } ? name : nil
        }
        return ["phase": phase, "uptime_seconds": ProcessInfo.processInfo.systemUptime,
            "cpu_seconds": cpuSeconds(), "physical_footprint_bytes": status == KERN_SUCCESS ? info.phys_footprint : 0,
            "resident_bytes": status == KERN_SUCCESS ? info.resident_size : 0, "loaded_ocr_frameworks": frameworks]
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        _ = getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
            Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
