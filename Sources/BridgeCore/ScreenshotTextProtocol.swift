import Foundation

public enum ScreenshotTextBudget {
    public static let workerArgument = "--recognize-screenshot-text"
    public static let workerExecutableName = "WindowsMacBridgeTextWorker"
    public static let maximumDimension = 2560
    public static let maximumPixels = 4_000_000
    public static let maximumUTF8Bytes = 64 * 1024
    public static let maximumLines = 1000
    // JSON escapes can expand an individual byte to six ASCII bytes.
    public static let maximumReplyBytes = maximumUTF8Bytes * 6 + 1024

    public static func combine(_ lines: [String]) -> Result<String, ScreenshotFailure> {
        guard lines.count <= maximumLines else { return .failure(.textTooLarge) }
        var result = "", bytes = 0
        for line in lines {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let count = value.utf8.count + (result.isEmpty ? 0 : 1)
            guard count <= maximumUTF8Bytes - bytes else { return .failure(.textTooLarge) }
            if !result.isEmpty { result.append("\n") }
            result.append(value); bytes += count
        }
        return result.isEmpty ? .failure(.textNotFound) : .success(result)
    }
}

public struct ScreenshotTextReply: Codable {
    var text: String?
    var failure: String?
    public init(_ result: Result<String, ScreenshotFailure>) {
        switch result {
        case .success(let value): text = value
        case .failure(let value): failure = value.rawValue
        }
    }
    public func result(exitCode: Int32) -> Result<String, ScreenshotFailure> {
        if let failure, let value = ScreenshotFailure(rawValue: failure) { return .failure(value) }
        guard exitCode == 0, let text else { return .failure(.recognitionFailure) }
        guard text.utf8.count <= ScreenshotTextBudget.maximumUTF8Bytes else { return .failure(.textTooLarge) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.textNotFound) }
        return .success(text)
    }
}
