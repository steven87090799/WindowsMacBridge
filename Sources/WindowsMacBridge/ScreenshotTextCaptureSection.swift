import SwiftUI
import BridgePlatform

struct ScreenshotTextCaptureSection: View {
    let status: ScreenshotStatus
    let canCapture: Bool
    let featuresEnabled: Bool
    var onCapture: () -> Void = {}
    var onCancel: () -> Void = {}
    var body: some View {
        Section("截圖文字擷取") {
            Text("框選畫面中的文字，使用 Apple Vision 在本機辨識繁體中文及英文，再複製文字。只在按下按鈕時執行，完成後釋放辨識程序。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("框選擷取文字…", action: onCapture).disabled(!canCapture)
                if status.isBusy { Button("取消截圖／辨識", action: onCancel) }
            }
            Text(status.lastResult).font(.caption).foregroundStyle(.secondary)
            if let issue = status.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if !featuresEnabled {
                Text("請先開啟 Windows 模式總開關與 Windows 快捷截圖。").font(.caption).foregroundStyle(.secondary)
            }
            Text("文字擷取沿用螢幕錄製授權；不會上傳、記錄辨識文字或自動辨識一般截圖。圖片與文字共用一個工作；取消或暫停後不覆寫剪貼簿。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
