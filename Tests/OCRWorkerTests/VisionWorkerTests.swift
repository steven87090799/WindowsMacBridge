import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Testing
import BridgeCore
@testable import WindowsMacBridgeTextWorker

struct VisionWorkerTests {
    @Test func realVisionRecognizesGeneratedTextWithoutScreenCapture() async throws {
        let png = try generatedTextPNG()
        let result = await Task.detached { VisionScreenshotText.recognize(png: png) }.value
        let text = try result.get()
        #expect(text.uppercased().contains("SCREEN TEXT 123"))
        #expect(text.utf8.count <= ScreenshotTextBudget.maximumUTF8Bytes)
    }
    @Test func invalidImagesAreRejectedBeforeVision() {
        for bytes in [Data(), Data("not an image".utf8)] {
            #expect(VisionScreenshotText.recognize(png: bytes) == .failure(.decodeFailure))
        }
    }
    private func generatedTextPNG() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 900, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 900, height: 180))
        let font = CTFontCreateWithName("Helvetica" as CFString, 58, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "SCREEN TEXT 123", attributes: attributes))
        context.textPosition = CGPoint(x: 30, y: 65); CTLineDraw(line, context)
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
