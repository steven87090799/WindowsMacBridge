import Foundation
import BridgeCore

public struct ApplicationRegistry: Sendable {
    public let entries: [String: ApplicationMode]
    private let remoteBundles: [NSRegularExpression]
    private let remotePaths: [NSRegularExpression]
    private let browsers: [NSRegularExpression]
    private let excluded: [NSRegularExpression]
    private struct Patterns: Decodable {
        var remoteBundlePatterns: [String]
        var remotePathPatterns: [String]
        var browserBundlePatterns: [String]
        var generalExcludedPatterns: [String]
    }
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
        guard let scopesURL = resources.url(forResource: "compatibility-applications", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let scopes = try JSONDecoder().decode(Patterns.self, from: Data(contentsOf: scopesURL))
        remoteBundles = try scopes.remoteBundlePatterns.map { try NSRegularExpression(pattern: $0) }
        remotePaths = try scopes.remotePathPatterns.map { try NSRegularExpression(pattern: $0) }
        browsers = try scopes.browserBundlePatterns.map { try NSRegularExpression(pattern: $0) }
        excluded = try scopes.generalExcludedPatterns.map { try NSRegularExpression(pattern: $0) }
    }
    private func matches(_ value: String, _ patterns: [NSRegularExpression]) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return patterns.contains { $0.firstMatch(in: value, range: range) != nil }
    }
    public func isBrowser(_ bundleID: String) -> Bool { matches(bundleID, browsers) }
    public func mode(for bundleID: String, executablePath: String = "", overrides: [String: ApplicationMode]) -> ApplicationMode {
        if let mode = overrides[bundleID] { return mode }
        if let mode = entries[bundleID] { return mode }
        // Conservative families: applications with embedded terminals / Windows guests.
        if bundleID.hasPrefix("com.jetbrains.") { return .ide }
        if bundleID.hasPrefix("com.parallels.") || bundleID.hasPrefix("com.vmware.") { return .virtualMachine }
        if matches(bundleID, remoteBundles) || matches(executablePath, remotePaths) { return .remoteWindows }
        if bundleID.hasPrefix("com.codeweavers.") || bundleID.hasPrefix("org.winehq.") { return .disabled }
        if bundleID != "com.apple.finder", matches(bundleID, excluded) {
            return bundleID.hasPrefix("dev.warp.") ? .terminal : .ide
        }
        return bundleID.isEmpty ? .disabled : .macOS
    }
}
