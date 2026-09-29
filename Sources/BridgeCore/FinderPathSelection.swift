import Foundation

/// Pure path selection shared by the app tests and the Finder Sync extension.
public enum FinderPathSelection {
    public static func folder(targetedURL: URL?, itemTarget: Bool = false) -> String? {
        guard let targetedURL, targetedURL.isFileURL else { return nil }
        return itemTarget ? targetedURL.deletingLastPathComponent().path : targetedURL.path
    }
    public static func selected(_ urls: [URL]) -> String? {
        let paths = urls.filter(\.isFileURL).map(\.path)
        return paths.isEmpty ? nil : paths.joined(separator: "\n")
    }
    public static func displayed(selectedURLs: [URL], targetedURL: URL?, itemTarget: Bool = false) -> String? {
        selectedURLs.first(where: \.isFileURL)?.path ?? folder(targetedURL: targetedURL, itemTarget: itemTarget)
    }
}
