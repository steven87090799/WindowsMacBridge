import Foundation
import BridgeCore

public struct ApplicationRegistry: Sendable {
    public let entries: [String: ApplicationMode]
    public init() throws {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.url(forResource: "WindowsMacBridge_BridgePlatform", withExtension: "bundle"),
                  let packaged = Bundle(url: url) else { throw CocoaError(.fileNoSuchFile) }
            resources = packaged
        } else { resources = Bundle.module }
        guard let url = resources.url(forResource: "applications", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        entries = try JSONDecoder().decode([String: ApplicationMode].self, from: Data(contentsOf: url))
    }
    public func mode(for bundleID: String, overrides: [String: ApplicationMode]) -> ApplicationMode {
        if let mode = overrides[bundleID] { return mode }
        if let mode = entries[bundleID] { return mode }
        // Conservative families: applications with embedded terminals / Windows guests.
        if bundleID.hasPrefix("com.jetbrains.") { return .ide }
        if bundleID.hasPrefix("com.parallels.") || bundleID.hasPrefix("com.vmware.") { return .virtualMachine }
        if bundleID.hasPrefix("com.codeweavers.") || bundleID.hasPrefix("org.winehq.") { return .disabled }
        return bundleID.isEmpty ? .disabled : .macOS
    }
}
