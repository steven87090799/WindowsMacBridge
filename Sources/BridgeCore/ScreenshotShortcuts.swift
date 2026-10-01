public enum ScreenshotKind: String, CaseIterable, Sendable { case region, activeWindow, fullScreen, fullScreenSave }
public enum PrintScreenBehavior: String, Codable, CaseIterable, Sendable {
    case snipping, fullScreenClipboard
    public var title: String { self == .snipping ? "開啟框選截圖" : "全螢幕複製" }
}
public enum WindowsScreenshotShortcuts {
    public static func match(key: UInt16, modifiers: Modifiers, windowsKey: WindowsKeyModifier,
                             printScreen: PrintScreenBehavior) -> ScreenshotKind? {
        if key == 1 && modifiers == [windowsKey.flag, .shift] { return .region }
        guard key == 105 else { return nil }
        if modifiers.isEmpty { return printScreen == .snipping ? .region : .fullScreen }
        if modifiers == windowsKey.altFlag { return .activeWindow }
        if modifiers == windowsKey.flag { return .fullScreenSave }
        return nil
    }
}
