import Foundation
import Darwin

/// One immutable, bounded snapshot of a capture file. Validation and every
/// later parse use the same descriptor's bytes, so a path that is replaced,
/// truncated or grown after the size check cannot bypass the budget. Never mapped.
public enum BoundedImageFile {
    public static func read(_ url: URL, limit: Int = ImageMemoryBudget.maximumFileBytes,
                     afterValidation: (() -> Void)? = nil) -> Result<Data, ScreenshotFailure> {
        // O_NONBLOCK: a FIFO at this path must not block the open.
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return .failure(.diskFailure) }
        defer { close(descriptor) }
        return read(descriptor: descriptor, limit: limit, afterValidation: afterValidation)
    }
    /// The OCR worker receives an already unlinked regular-file snapshot on stdin.
    /// The caller owns this descriptor; all size/type/readback checks stay shared.
    public static func read(descriptor: Int32, limit: Int = ImageMemoryBudget.maximumFileBytes,
                     afterValidation: (() -> Void)? = nil) -> Result<Data, ScreenshotFailure> {
        guard limit > 0 else { return .failure(.diskFailure) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= off_t(min(limit, ImageMemoryBudget.maximumFileBytes)) else { return .failure(.diskFailure) }
        afterValidation?()
        let expected = Int(before.st_size)
        // One extra byte detects growth; the allocation is bounded by the validated size.
        var data = Data(count: expected + 1)
        var total = 0
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while total < buffer.count {
                guard !Task.isCancelled else { return false }
                let count = Darwin.read(descriptor, base.advanced(by: total), buffer.count - total)
                if count < 0 { if errno == EINTR { continue }; return false }
                if count == 0 { break }
                total += count
            }
            return true
        }
        guard !Task.isCancelled else { return .failure(.policyCancelled) }
        var after = stat()
        guard complete, total == expected, fstat(descriptor, &after) == 0, after.st_size == before.st_size,
              after.st_ino == before.st_ino, after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { return .failure(.diskFailure) }
        data.count = expected
        return .success(data)
    }
}
