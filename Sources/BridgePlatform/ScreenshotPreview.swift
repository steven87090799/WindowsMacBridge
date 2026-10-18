import Foundation
import ImageIO
import CoreGraphics
import BridgeCore

/// Only a small encoded thumbnail crosses to the UI. The original stays on disk
/// until dismissal or until the user closes their explicitly opened preview.
public struct ScreenshotPreview: Sendable {
    public let thumbnailPNG: Data
    public let sourceURL: URL
    public let ownsSourceFile: Bool
    public init(thumbnailPNG: Data, sourceURL: URL, ownsSourceFile: Bool) {
        self.thumbnailPNG = thumbnailPNG; self.sourceURL = sourceURL; self.ownsSourceFile = ownsSourceFile
    }
}

public enum ScreenshotPreviewPreparation {
    public static let maximumDimension = 720
    public static let maximumPNGBytes = 1024 * 1024
    public static func thumbnail(png: Data) -> Data? {
        autoreleasepool {
            guard !Task.isCancelled, !png.isEmpty, png.count <= ImageMemoryBudget.maximumFileBytes,
                  let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, (1...16).contains(depth),
                  ImageMemoryBudget.allows(width: width, height: height, bytesPerPixel: 4 * ((depth + 7) / 8)),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                    kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                  image.width <= maximumDimension, image.height <= maximumDimension else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination), data.length <= maximumPNGBytes, !Task.isCancelled else { return nil }
            return data as Data
        }
    }
}
