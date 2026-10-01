public enum ImageMemoryBudget {
    public static let maximumFileBytes = 64 * 1024 * 1024
    public static let maximumDimension = 16_384
    public static let maximumPixels = 36_000_000
    public static let maximumDecodedBytes = 144 * 1024 * 1024
    public static func allows(width: Int, height: Int, bytesPerPixel: Int) -> Bool {
        guard width > 0, height > 0, bytesPerPixel > 0,
              width <= maximumDimension, height <= maximumDimension else { return false }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow, pixels.partialValue <= maximumPixels else { return false }
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: bytesPerPixel)
        return !bytes.overflow && bytes.partialValue <= maximumDecodedBytes
    }
}
public enum ScreenshotFailure: String, Error, Sendable {
    case userCancelled, permissionDenied, processFailure, diskFailure, decodeFailure, encodeFailure, timedOut, policyCancelled
    public static func classify(exitCode: Int32, hasImage: Bool, permission: Bool, writable: Bool,
                                interactive: Bool = true) -> Self? {
        if !permission { return .permissionDenied }
        if !writable { return .diskFailure }
        if exitCode != 0 { return .processFailure }
        return hasImage ? nil : (interactive ? .userCancelled : .processFailure)
    }
}
