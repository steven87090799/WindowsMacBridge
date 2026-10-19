import SwiftUI

extension SettingsPage {
    var symbol: String {
        switch self {
        case .permissions: "lock.shield"
        case .general: "slider.horizontal.3"
        case .inputSources: "character.bubble"
        case .profiles: "app.badge"
        case .preview: "keyboard"
        case .remoteCalibration: "desktopcomputer.and.arrow.down"
        case .performance: "gauge.with.dots.needle.33percent"
        case .diagnostics: "waveform.path.ecg"
        }
    }

    var detail: String {
        switch self {
        case .permissions: "確認鍵盤、截圖與登入權限"
        case .general: "讓熟悉的 Windows 操作融入 Mac"
        case .inputSources: "管理唯音繁體、ABC 與切換快捷鍵"
        case .profiles: "為不同 App 選擇適合的按鍵規則"
        case .preview: "啟用之前，先確認每個組合的輸出"
        case .remoteCalibration: "辨識其他電腦傳入這台 Mac 的按鍵"
        case .performance: "查看目前用量；離開此頁即停止取樣"
        case .diagnostics: "查看引擎狀態與版本資訊"
        }
    }
}

/// A fixed settings sidebar and grouped forms in a standard macOS window.
/// Injected content keeps visual checks independent of live input services.
struct GlassSettingsChrome<Content: View>: View {
    @Binding var selection: SettingsPage
    let advanced: Bool
    let isOperating: Bool
    let status: String
    let version: String
    var onHelp: () -> Void = {}
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                SettingsNavigation(selection: $selection, advanced: advanced)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Circle().fill(isOperating ? Color.green : Color.secondary).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(isOperating ? "運作中" : "未運作").font(.caption.weight(.medium))
                        Spacer()
                        Text(version).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        Spacer(minLength: 0)
                        Button(action: onHelp) { Label("使用說明", systemImage: "questionmark.circle").labelStyle(.iconOnly) }
                            .buttonStyle(.plain).focusEffectDisabled().help("開啟使用說明")
                    }
                }
                .padding(16)
            }
            .frame(width: 218)
            .frame(maxHeight: .infinity)
            .bridgeNavigationSurface()
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.rawValue).font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(selection.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 10)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .clipped()
        .frame(minWidth: 730, minHeight: 600)
    }
}
