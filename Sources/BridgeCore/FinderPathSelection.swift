import Foundation

/// Pure path selection shared by the app tests and the Finder Sync extension.
public enum FinderPathSelection {
    public static func folder(targetedURL: URL?, selectedURLs: [URL] = [], itemTarget: Bool = false) -> String? {
        if itemTarget, let selected = selectedURLs.first(where: \.isFileURL) {
            return selected.deletingLastPathComponent().path
        }
        guard let targetedURL, targetedURL.isFileURL else { return nil }
        return itemTarget ? targetedURL.deletingLastPathComponent().path : targetedURL.path
    }
    public static func selected(_ urls: [URL]) -> String? {
        guard urls.count <= 1024 else { return nil }
        var paths: [String] = []
        var bytes = 0
        for url in urls where url.isFileURL {
            let path = url.path
            bytes += path.utf8.count + 1
            guard bytes <= 1024 * 1024 else { return nil }
            paths.append(path)
        }
        return paths.isEmpty ? nil : paths.joined(separator: "\n")
    }
    public static func displayed(selectedURLs: [URL], targetedURL: URL?, itemTarget: Bool = false) -> String? {
        selectedURLs.first(where: \.isFileURL)?.path ?? folder(targetedURL: targetedURL, itemTarget: itemTarget)
    }
}
