import Foundation
import CoreServices
import Darwin
import BridgeCore

/// Observe files produced by macOS itself, after its cross-machine routing and
/// screenshot UI have finished. No early key interception, folder polling or
/// global screenshot preference changes are needed for Command-Shift-3/4.
@MainActor final class NativeScreenshotObserver {
    private var stream: FSEventStreamRef?
    private var directory: URL?
    private var startedAt = Date.distantFuture
    private var generation: UInt64 = 0
    private var seen: [(URL, Date)] = []
    private var pending: [URL] = []
    private var resolving = false
    private var lastDelivered = Date.distantPast
    var onScreenshot: ((URL) -> Void)?

    isolated deinit { stop() }

    func start(directory: URL) -> Bool {
        let directory = directory.resolvingSymlinksInPath().standardizedFileURL
        if stream != nil && self.directory == directory { return true }
        stop()
        self.directory = directory; startedAt = Date()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let owner = Unmanaged<NativeScreenshotObserver>.fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue; its context is destroyed
            // synchronously on that same queue before releasing the observer.
            MainActor.assumeIsolated {
                let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                var urls: [URL] = []
                for i in max(0, count - 64)..<count {
                    guard flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 else { continue }
                    urls.append(URL(fileURLWithPath: String(cString: paths[i])))
                }
                owner.receive(urls)
            }
        }
        guard let next = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return false }
        FSEventStreamSetDispatchQueue(next, .main)
        guard FSEventStreamStart(next) else { FSEventStreamInvalidate(next); FSEventStreamRelease(next); return false }
        stream = next
        return true
    }

    func stop() {
        generation &+= 1
        if let stream {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        }
        stream = nil; directory = nil; seen.removeAll(); pending.removeAll()
        lastDelivered = .distantPast
    }

    private func receive(_ urls: [URL]) {
        guard let directory else { return }
        // Drop unrelated desktop files before scheduling a metadata worker.
        for url in urls where Self.isCandidatePath(url, directory: directory) && !pending.contains(url) {
            if pending.count == 64 { pending.removeFirst() }
            pending.append(url)
        }
        guard !resolving, !pending.isEmpty else { return }
        resolving = true
        let epoch = generation, since = startedAt
        // Only metadata checks and image preparation leave the main actor. A
        // stopped/restarted observer cannot deliver a late clipboard candidate.
        // FSEvents batches are capped above; duplicate paths are removed here.
        let candidates = pending; pending.removeAll()
        Task { [weak self] in
            let matches = await Task.detached(priority: .utility) {
                candidates.compactMap { url -> (URL, Date)? in
                    guard let date = Self.screenshotDate(url, directory: directory, since: since) else { return nil }
                    return (url, date)
                }.sorted { $0.1 > $1.1 }
            }.value
            guard let self else { return }
            self.resolving = false
            defer { self.receive([]) }
            guard self.generation == epoch, self.stream != nil else { return }
            guard let match = matches.first(where: { candidate in
                candidate.1 >= self.lastDelivered && !self.seen.contains { $0.0 == candidate.0 && $0.1 == candidate.1 }
            }) else { return }
            self.lastDelivered = match.1
            self.seen.append(match)
            if self.seen.count > 32 { self.seen.removeFirst(self.seen.count - 32) }
            self.onScreenshot?(match.0)
        }
    }

    nonisolated private static func isCandidatePath(_ url: URL, directory: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL &&
            !url.lastPathComponent.hasPrefix("WindowsMacBridge Screenshot ") &&
            ["png", "jpg", "jpeg", "tiff", "tif", "pdf"].contains(url.pathExtension.lowercased())
    }

    nonisolated static func screenshotDate(_ url: URL, directory: URL, since: Date) -> Date? {
        guard isCandidatePath(url, directory: directory),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let date = values.creationDate, date >= since,
              let size = values.fileSize, size > 0, size <= ImageMemoryBudget.maximumFileBytes else { return nil }
        // File names and extensions are not evidence of a screenshot. Require
        // the metadata written by Apple's screenshot service before reading pixels.
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let length = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0, length <= 1024 else { return nil }
        var data = Data(count: length)
        let actual = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, length, 0, XATTR_NOFOLLOW) }
        guard actual == length,
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue else { return nil }
        return date
    }
}
