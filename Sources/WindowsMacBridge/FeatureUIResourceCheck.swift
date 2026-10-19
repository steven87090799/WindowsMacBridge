import AppKit
import SwiftUI
import Darwin
import MachO
import BridgePlatform

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
        guard arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--suspension-only") else { exit(64) }
        let destination = URL(fileURLWithPath: arguments[1])
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            NSApplication.shared.setActivationPolicy(.prohibited)
            var observations = [[String: Any]]()
            var owners = [WeakObject]()
            if arguments.count == 3 {
                try exerciseSuspendedSettings(count: 5, owners: &owners)
                drain(seconds: 2)
                let retained = owners.filter { $0.value != nil }.map(\.kind)
                let windows = owners.compactMap { owner -> [String: Any]? in
                    guard let window = owner.value as? NSWindow else { return nil }
                    return ["kind": owner.kind, "visible": window.isVisible,
                        "in_app_windows": NSApp.windows.contains { $0 === window },
                        "window_controller": String(describing: window.windowController),
                        "delegate": String(describing: window.delegate),
                        "toolbar": String(describing: window.toolbar),
                        "content_controller": String(describing: window.contentViewController),
                        "content_view": String(describing: window.contentView),
                        "first_responder": String(describing: window.firstResponder)]
                }
                let result: [String: Any] = ["scope": "generated-suspended-window-ownership-only",
                    "weak_objects_checked": owners.count, "retained_objects": retained, "retained_windows": windows]
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: destination, options: .withoutOverwriting)
                print("Suspension check: \(owners.count) weak owners, \(retained.count) retained")
                if !retained.isEmpty { exit(1) }
                return true
            }
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
            let visibilityChecks = try verifyPerformanceVisibility(owners: &owners)
            exercisePerformance(count: 10, owners: &owners)
            try exerciseNavigation(count: 10, owners: &owners)
            try exerciseSuspendedSettings(count: 5, owners: &owners)
            drain(seconds: 2)
            let finalIdleCPU = cpuSeconds(), finalIdleStart = ProcessInfo.processInfo.systemUptime
            drain(seconds: 30)
            let finalCPU = cpuSeconds() - finalIdleCPU
            let finalWall = ProcessInfo.processInfo.systemUptime - finalIdleStart
            observations.append(snapshot("final-closed"))
            let retained = owners.filter { $0.value != nil }.map(\.kind)
            let result: [String: Any] = [
                "scope": "generated-offscreen-UI-only-no-input-engine-no-GPU-measurement",
                "settings_cycles": 33, "panel_cycles": 33,
                "performance_page_cycles": 10, "performance_visibility_checks": visibilityChecks,
                "navigation_cycles": 10, "navigation_selections": 80, "tab_traversals_without_selection_change": 120,
                "suspended_and_restored_windows": 5,
                "weak_objects_checked": owners.count, "retained_objects": retained,
                "closed_idle_wall_seconds": closedWall, "closed_idle_cpu_seconds": closedCPU,
                "closed_idle_single_core_cpu_percent": closedCPU / closedWall * 100,
                "after_navigation_closed_idle_wall_seconds": finalWall,
                "after_navigation_closed_idle_cpu_seconds": finalCPU,
                "after_navigation_closed_idle_single_core_cpu_percent": finalCPU / finalWall * 100,
                "observations": observations
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination, options: .withoutOverwriting)
            print("UI resource check: \(owners.count) weak owners, \(retained.count) retained; \(destination.path)")
            if !retained.isEmpty { exit(1) }
        } catch { print("UI resource check failed: \(error)"); exit(1) }
        return true
    }

    private final class VisibilityFixtureWindow: NSWindow {
        var fixtureVisible = false
        var fixtureOccluded = false
        var fixtureMiniaturized = false
        override var isVisible: Bool { fixtureVisible }
        override var isMiniaturized: Bool { fixtureMiniaturized }
        override var occlusionState: NSWindow.OcclusionState { fixtureOccluded ? [] : [.visible] }
    }

    private static func verifyPerformanceVisibility(owners: inout [WeakObject]) throws -> [String] {
        var checks = [String]()
        try autoreleasepool {
            let monitor = PerformanceMonitor()
            let probe = PerformanceVisibilityView()
            probe.onChange = { [weak monitor] in monitor?.setVisible($0) }
            let window = VisibilityFixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = probe
            owners.append(WeakObject(monitor, kind: "visibility-monitor"))
            owners.append(WeakObject(probe, kind: "visibility-observer"))
            owners.append(WeakObject(window, kind: "visibility-window"))
            @MainActor func check(_ label: String, sampling: Bool) throws {
                NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
                drain(seconds: 0.05)
                guard monitor.isSampling == sampling else { throw CocoaError(.validationMissingMandatoryProperty) }
                checks.append(label)
            }
            try check("never-shown-window-stopped", sampling: false)
            window.fixtureVisible = true
            try check("visible-page-started", sampling: true)
            window.fixtureOccluded = true
            try check("occluded-window-stopped", sampling: false)
            window.fixtureOccluded = false
            try check("uncovered-page-restarted", sampling: true)
            window.fixtureMiniaturized = true
            try check("minimized-window-stopped", sampling: false)
            window.fixtureMiniaturized = false
            try check("restored-page-restarted", sampling: true)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            try check("sleep-stopped", sampling: false)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            try check("wake-restarted", sampling: true)
            window.contentView = nil
            try check("removed-page-stopped", sampling: false)
            window.contentView = probe
            try check("reattached-page-restarted", sampling: true)
            window.close()
            try check("closed-window-stopped", sampling: false)
            window.contentView = nil
        }
        return checks
    }

    private static func exercisePerformance(count: Int, owners: inout [WeakObject]) {
        for _ in 0..<count {
            autoreleasepool {
                let monitor = PerformanceMonitor()
                let window = SettingsWindowFactory.make(content: PerformanceView(monitor: monitor))
                owners.append(WeakObject(monitor, kind: "performance-monitor"))
                owners.append(WeakObject(window, kind: "performance-window"))
                if let host = window.contentViewController { owners.append(WeakObject(host, kind: "performance-host")) }
                window.contentView?.layoutSubtreeIfNeeded()
                SettingsWindowFactory.releaseContent(of: window)
                window.close()
            }
            drain(seconds: 0.05)
        }
    }

    private final class NavigationFixture: ObservableObject {
        @Published var selection: SettingsPage = .general
    }

    private struct NavigationFixtureView: View {
        @ObservedObject var model: NavigationFixture
        var body: some View {
            GlassSettingsChrome(selection: $model.selection, advanced: true, isOperating: true,
                status: "Generated navigation fixture", version: "fixture") {
                Form { Text("Generated content only; no live services") }.formStyle(.grouped)
            }
        }
    }

    private static func exerciseNavigation(count: Int, owners: inout [WeakObject]) throws {
        for _ in 0..<count {
            try autoreleasepool {
                let model = NavigationFixture()
                let window = SettingsWindowFactory.make(content: NavigationFixtureView(model: model))
                owners.append(WeakObject(model, kind: "navigation-state"))
                owners.append(WeakObject(window, kind: "navigation-window"))
                if let host = window.contentViewController { owners.append(WeakObject(host, kind: "navigation-host")) }
                if let view = window.contentView { owners.append(WeakObject(view, kind: "navigation-view")) }
                for page in SettingsPage.allCases {
                    model.selection = page
                    window.contentView?.layoutSubtreeIfNeeded()
                    drain(seconds: 0.02)
                }
                // Tab moves focus; it must never silently change the page.
                let beforeTab = model.selection
                for _ in 0..<12 { window.selectNextKeyView(nil) }
                guard model.selection == beforeTab else { throw CocoaError(.validationMultipleErrors) }
                // Interrupt the last finite glass transition by releasing it.
                SettingsWindowFactory.releaseContent(of: window)
                window.close()
            }
            drain(seconds: 0.08)
        }
    }

    private static func exerciseSuspendedSettings(count: Int, owners: inout [WeakObject]) throws {
        for _ in 0..<count {
            var window: NSWindow?
            var originalFrame = NSRect.zero
            var suspendedOwners = [WeakObject]()
            autoreleasepool {
                let model = NavigationFixture()
                let created = SettingsWindowFactory.make(content: NavigationFixtureView(model: model))
                window = created
                suspendedOwners.append(WeakObject(model, kind: "suspended-navigation-state"))
                if let host = created.contentViewController { suspendedOwners.append(WeakObject(host, kind: "suspended-host")) }
                if let view = created.contentView { suspendedOwners.append(WeakObject(view, kind: "suspended-view")) }
                created.contentView?.layoutSubtreeIfNeeded()
                originalFrame = created.frame
                SettingsWindowFactory.releaseContent(of: created)
            }
            drain(seconds: 0.15)
            // Hide/minimize retains the NSWindow but must release its entire UI.
            guard suspendedOwners.allSatisfy({ $0.value == nil }) else {
                throw NSError(domain: "UIResourceCheck", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Suspended window retained UI: \(suspendedOwners.filter { $0.value != nil }.map(\.kind))"])
            }
            owners.append(contentsOf: suspendedOwners)
            // close() autoreleases AppKit objects. In this explicit CLI probe
            // NSApplication.run() is never entered, so give teardown its own
            // event-equivalent pool instead of retaining it until process exit.
            try autoreleasepool {
                guard let current = window else { throw CocoaError(.validationMultipleErrors) }
                owners.append(WeakObject(current, kind: "suspended-restored-window"))
                let frame = current.frame
                guard frame == originalFrame else { throw CocoaError(.validationMultipleErrors) }
                let model = NavigationFixture()
                model.selection = .performance
                SettingsWindowFactory.restoreContent(of: current, content: NavigationFixtureView(model: model))
                owners.append(WeakObject(model, kind: "restored-navigation-state"))
                if let host = current.contentViewController { owners.append(WeakObject(host, kind: "restored-host")) }
                if let view = current.contentView { owners.append(WeakObject(view, kind: "restored-view")) }
                current.contentView?.layoutSubtreeIfNeeded()
                SettingsWindowFactory.releaseContent(of: current)
                guard current.frame == frame else { throw CocoaError(.validationMultipleErrors) }
                current.close(); window = nil
            }
            drain(seconds: 0.1)
        }
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
