import Foundation
import ImageIO
import Vision
import Darwin
import BridgeCore

/// Called in the short-lived OCR worker, never by the keyboard callback or an
/// idle task. Vision's model cache dies with that worker rather than the App.
public enum VisionScreenshotText {
    public static func recognize(png: Data) -> Result<String, ScreenshotFailure> {
        autoreleasepool {
            guard !png.isEmpty, png.count <= ImageMemoryBudget.maximumFileBytes,
                  let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, (1...16).contains(depth),
                  ImageMemoryBudget.allows(width: width, height: height, bytesPerPixel: 4 * ((depth + 7) / 8)) else { return .failure(.decodeFailure) }
            let scale = min(1, Double(ScreenshotTextBudget.maximumDimension) / Double(max(width, height)),
                            sqrt(Double(ScreenshotTextBudget.maximumPixels) / Double(width * height)))
            let side = max(1, Int(floor(Double(max(width, height)) * scale)))
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: side,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  image.width * image.height <= ScreenshotTextBudget.maximumPixels,
                  max(image.width, image.height) <= ScreenshotTextBudget.maximumDimension else { return .failure(.decodeFailure) }
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.preferBackgroundProcessing = true
                let supported = try request.supportedRecognitionLanguages()
                request.recognitionLanguages = ["zh-Hant", "en-US"].filter { supported.contains($0) }
                guard !request.recognitionLanguages.isEmpty else { return .failure(.recognitionFailure) }
                // Chinese has no language correction; preserve literal code and identifiers too.
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                let observations = request.results ?? []
                guard observations.count <= ScreenshotTextBudget.maximumLines else { return .failure(.textTooLarge) }
                return ScreenshotTextBudget.combine(observations.compactMap { $0.topCandidates(1).first?.string })
            } catch { return .failure(.recognitionFailure) }
        }
    }
}

public enum ScreenshotTextWorker {
    public static let argument = ScreenshotTextBudget.workerArgument
    /// Explicit CLI worker branch, before AppKit, TIS, EventTap or HID startup.
    public static func handle(_ arguments: [String]) -> Bool {
        guard arguments.first == argument else { return false }
        // A quit/crash of the GUI must not orphan a model-heavy OCR process.
        // One kernel exit notification, only during this explicit worker job.
        let parent = getppid()
        guard parent > 1 else { _exit(125) }
        let parentExit = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global(qos: .utility))
        parentExit.setEventHandler { _exit(125) }
        parentExit.resume()
        defer { parentExit.cancel() }
        guard getppid() == parent else { _exit(125) }
        let result: Result<String, ScreenshotFailure>
        if arguments.count == 1 {
            result = BoundedImageFile.read(descriptor: STDIN_FILENO).flatMap { VisionScreenshotText.recognize(png: $0) }
        } else if arguments.count == 2 {
            result = BoundedImageFile.read(URL(fileURLWithPath: arguments[1])).flatMap { VisionScreenshotText.recognize(png: $0) }
        } else { result = .failure(.decodeFailure) }
        if let data = try? JSONEncoder().encode(ScreenshotTextReply(result)), data.count <= ScreenshotTextBudget.maximumReplyBytes {
            try? FileHandle.standardOutput.write(contentsOf: data)
        }
        return true
    }
}
