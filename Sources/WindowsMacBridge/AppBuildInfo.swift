import AppKit

@MainActor struct AppBuildInfo {
    static let current = Self(bundle: .main)

    let version: String
    let buildNumber: String
    let buildDateUTC: String
    let gitRevision: String
    let sourceState: String
    let bundleIdentifier: String

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        buildDateUTC = bundle.object(forInfoDictionaryKey: "WMBBuildDateUTC") as? String ?? "unknown"
        gitRevision = bundle.object(forInfoDictionaryKey: "WMBGitRevision") as? String ?? "unknown"
        sourceState = bundle.object(forInfoDictionaryKey: "WMBSourceState") as? String ?? "unknown"
        bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
    }

    var versionLabel: String { "\(version) (\(buildNumber))" }
    var shortRevision: String { String(gitRevision.prefix(12)) }
    var diagnosticText: String {
        "WindowsMacBridge \(versionLabel)\nBuild UTC: \(buildDateUTC)\nGit: \(gitRevision) (\(sourceState))\nBundle ID: \(bundleIdentifier)"
    }

    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticText, forType: .string)
    }
}
