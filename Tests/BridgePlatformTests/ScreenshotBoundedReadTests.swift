import AppKit
import Darwin
import Foundation
import ImageIO
import Testing
import BridgeCore
@testable import BridgePlatform

private final class TemporaryDirectory {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wmb-bounded-\(UUID().uuidString)", isDirectory: true)
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
}

private func pngData(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil); _ = CGImageDestinationFinalize(destination)
    return data as Data
}
/// A 1x1 PNG whose IHDR claims huge dimensions (CRC fixed), i.e. a tiny file
/// that would decode to an enormous bitmap.
private func pngClaiming(width: UInt32, height: UInt32) -> Data {
    var bytes = [UInt8](pngData(width: 1, height: 1))
    func put(_ value: UInt32, at offset: Int) { for i in 0..<4 { bytes[offset + i] = UInt8((value >> (24 - 8 * UInt32(i))) & 0xff) } }
    put(width, at: 16); put(height, at: 20)
    var crc: UInt32 = 0xffffffff
    for byte in bytes[12..<29] {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) }
    }
    put(~crc, at: 29)
    return Data(bytes)
}
private func footprint() -> UInt64 {
    var info = task_vm_info_data_t(); var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

struct ScreenshotBoundedReadTests {
    @Test func validPNGUnderTheLimitIsHandedOverWithoutReencoding() throws {
        let directory = TemporaryDirectory(); let url = directory.file("capture.png")
        let original = pngData(width: 64, height: 32); try original.write(to: url)
        let payload = try ScreenshotImagePreparation.prepareResult(at: url).get()
        #expect(payload.png == original)
    }
    @Test func oversizedFileIsRejectedBeforeAnyRead() throws {
        let directory = TemporaryDirectory(); let url = directory.file("huge.png")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ImageMemoryBudget.maximumFileBytes + 1)); try handle.close()   // sparse
        let before = footprint()
        #expect(BoundedImageFile.read(url).failureValue == .diskFailure)
        #expect(footprint() < before + 16 * 1024 * 1024, "must not allocate the oversized file")
    }
    @Test func replacingThePathAfterValidationCannotSwapInDifferentOrLargerBytes() throws {
        let directory = TemporaryDirectory(); let url = directory.file("capture.png")
        let original = pngData(width: 8, height: 8); try original.write(to: url)
        let big = directory.file("big.bin")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big); try handle.truncate(atOffset: UInt64(ImageMemoryBudget.maximumFileBytes * 2)); try handle.close()
        let result = BoundedImageFile.read(url) { _ = rename(big.path, url.path) }
        // The descriptor's snapshot is the validated file; the replacement is never read.
        #expect(result.successValue == original)
    }
    @Test func truncationOrGrowthDuringTheReadFailsSafely() throws {
        let directory = TemporaryDirectory(); let url = directory.file("capture.png")
        try pngData(width: 32, height: 32).write(to: url)
        #expect(BoundedImageFile.read(url) { _ = truncate(url.path, 10) }.failureValue == .diskFailure)
        try pngData(width: 32, height: 32).write(to: url)
        let grow = { let h = try? FileHandle(forWritingTo: url); _ = try? h?.seekToEnd(); try? h?.write(contentsOf: Data(repeating: 0, count: 4096)); try? h?.close() }
        #expect(BoundedImageFile.read(url, afterValidation: grow).failureValue == .diskFailure)
    }
    @Test func symlinkFifoAndDirectoryAreRejectedWithoutBlocking() throws {
        let directory = TemporaryDirectory()
        let target = directory.file("target.png"); try pngData(width: 4, height: 4).write(to: target)
        let link = directory.file("link.png"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(BoundedImageFile.read(link).failureValue == .diskFailure)
        let fifo = directory.file("fifo.png"); #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(BoundedImageFile.read(fifo).failureValue == .diskFailure)
        #expect(BoundedImageFile.read(directory.url).failureValue == .diskFailure)
    }
    @Test func malformedAndHugeDimensionImagesAreRejectedBeforeDecode() throws {
        let directory = TemporaryDirectory()
        let malformed = directory.file("bad.png")
        try (Data([137, 80, 78, 71, 13, 10, 26, 10]) + Data(repeating: 7, count: 512)).write(to: malformed)
        #expect(ScreenshotImagePreparation.prepareResult(at: malformed).failureValue == .decodeFailure)
        let bomb = directory.file("bomb.png"); try pngClaiming(width: 100_000, height: 100_000).write(to: bomb)
        let before = footprint()
        #expect(ScreenshotImagePreparation.prepareResult(at: bomb).failureValue == .decodeFailure)
        #expect(footprint() < before + 64 * 1024 * 1024)
    }
    @Test func hugePDFMediaBoxIsRejected() throws {
        let directory = TemporaryDirectory(); let url = directory.file("capture.pdf")
        var box = CGRect(x: 0, y: 0, width: 200_000, height: 200_000)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        #expect(ScreenshotImagePreparation.prepareResult(at: url).failureValue == .decodeFailure)
    }
    @Test func cancellationBeforeOrDuringPreparationNeverProducesAPayload() async throws {
        let directory = TemporaryDirectory(); let url = directory.file("capture.tiff")
        let tiff = NSBitmapImageRep(data: pngData(width: 256, height: 256))!.tiffRepresentation!
        try tiff.write(to: url)
        let task = Task.detached { () -> Result<ScreenshotImagePayload, ScreenshotFailure> in
            withUnsafeCurrentTask { $0?.cancel() }
            return ScreenshotImagePreparation.prepareResult(at: url)
        }
        #expect(await task.value.failureValue == .policyCancelled)
        // Encoding refuses to grow its buffer once cancelled.
        let image = NSBitmapImageRep(data: tiff)!.cgImage!
        let encode = Task.detached { () -> Result<ScreenshotImagePayload, ScreenshotFailure> in
            withUnsafeCurrentTask { $0?.cancel() }
            return ScreenshotImagePreparation.encodePNG(image)
        }
        #expect(await encode.value.successValue == nil)
    }
    @Test func repeatedPreparationDoesNotGrowMemoryWithCaptureCount() throws {
        // phys_footprint is process-wide and other suites run concurrently, so the
        // bound is far below what a per-capture leak would add (~12 MiB decoded
        // bitmap per capture, ~700 MiB over 60) but above concurrent-test noise.
        let directory = TemporaryDirectory(); let url = directory.file("capture.tiff")
        try NSBitmapImageRep(data: pngData(width: 2048, height: 1536))!.tiffRepresentation!.write(to: url)
        // AddressSanitizer quarantines freed blocks (256 MiB by default), so the
        // footprint rises until the quarantine is full even without a leak. Fill
        // it first; a per-capture leak still grows past the bound afterwards.
        let warmUp = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__asan_init") == nil ? 3 : 40
        for _ in 0..<warmUp { autoreleasepool { _ = ScreenshotImagePreparation.prepareResult(at: url) } }   // warm caches
        let before = footprint()
        for _ in 0..<60 { autoreleasepool { _ = ScreenshotImagePreparation.prepareResult(at: url) } }
        #expect(footprint() < before + 128 * 1024 * 1024, "transient buffers must be released per capture")
    }
}

private extension Result {
    var successValue: Success? { if case .success(let value) = self { return value }; return nil }
    var failureValue: Failure? { if case .failure(let value) = self { return value }; return nil }
}
