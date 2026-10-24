import AppKit
import BridgeCore

@MainActor protocol RunningApplicationInfo {
    var processIdentifier: Int32 { get }
    var isTerminated: Bool { get }
    var bundleIdentifier: String? { get }
    var executableURL: URL? { get }
    var localizedName: String? { get }
}

extension NSRunningApplication: RunningApplicationInfo {}

/// NSWorkspace entries can outlive their processes, and a missing PID is -1.
/// Build a fresh, nontrapping recipient map from valid application identities.
@MainActor public enum RunningApplicationSnapshot {
    public static func contexts(for applications: [NSRunningApplication], registry: ApplicationRegistry?,
                                overrides: [String: ApplicationMode]) -> [Int32: ApplicationContext] {
        collect(applications, registry: registry, overrides: overrides)
    }

    public static func context(for application: NSRunningApplication, registry: ApplicationRegistry?,
                               overrides: [String: ApplicationMode]) -> ApplicationContext? {
        resolve(application, registry: registry, overrides: overrides)
    }

    static func collect<Application: RunningApplicationInfo>(_ applications: [Application], registry: ApplicationRegistry?,
                                                            overrides: [String: ApplicationMode]) -> [Int32: ApplicationContext] {
        var result: [Int32: ApplicationContext] = [:]
        for application in applications {
            guard let context = resolve(application, registry: registry, overrides: overrides) else { continue }
            // Repeated valid entries update their context instead of trapping.
            result[context.processID] = context
        }
        return result
    }

    static func resolve<Application: RunningApplicationInfo>(_ application: Application, registry: ApplicationRegistry?,
                                                            overrides: [String: ApplicationMode]) -> ApplicationContext? {
        // Capture the PID once so the dictionary key and its value cannot diverge.
        let pid = application.processIdentifier
        guard pid > 0, !application.isTerminated else { return nil }
        let bundle = application.bundleIdentifier ?? ""
        let path = application.executableURL?.path ?? ""
        let name = application.localizedName ?? "Unknown"
        guard !application.isTerminated else { return nil }
        return ApplicationContext(processID: pid, bundleID: bundle, displayName: name,
                                  mode: registry?.mode(for: bundle, executablePath: path, overrides: overrides) ?? .disabled,
                                  executablePath: path, isBrowser: registry?.isBrowser(bundle) ?? false)
    }
}
