import SwiftUI

private typealias NavigationState<Value> = SwiftUI.State<Value>

extension SettingsPage {
    var symbol: String {
        switch self {
        case .permissions: "lock.shield"
        case .general: "slider.horizontal.3"
        case .inputSources: "character.bubble"
        case .profiles: "app.badge"
        case .preview: "keyboard"
        case .remoteCalibration: "desktopcomputer.and.arrow.down"
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
        case .diagnostics: "查看引擎狀態與版本資訊"
        }
    }
}

/// Native split-view navigation, grouped forms and a standard macOS toolbar.
/// Injected content keeps visual checks independent of live input services.
struct GlassSettingsChrome<Content: View>: View {
    @Binding var selection: SettingsPage
    let advanced: Bool
    let isOperating: Bool
    let status: String
    let version: String
    var onHelp: () -> Void = {}
    @ViewBuilder var content: () -> Content
    @NavigationState private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding<SettingsPage?>(get: { selection }, set: { if let page = $0 { selection = page } })) {
                Section("設定") {
                    ForEach(SettingsPage.allCases.filter { advanced || $0 != .diagnostics }, id: \.self) { page in
                        HStack(spacing: 10) {
                            Image(systemName: page.symbol).renderingMode(.template)
                                .foregroundStyle(selection == page && controlActiveState == .key ?
                                    Color(nsColor: .selectedControlTextColor) : Color.primary)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(page.rawValue)
                        }
                        .tag(page)
                        .help(page.detail)
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 184, ideal: 214, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Circle().fill(isOperating ? Color.green : Color.secondary).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(isOperating ? "運作中" : "未運作").font(.caption.weight(.medium))
                        Spacer()
                        Text(version).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                .padding(16)
            }
        } detail: {
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
            .frame(minWidth: 500)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("WindowsMacBridge")
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Label("顯示或隱藏側邊欄", systemImage: "sidebar.left")
                }
                .help("顯示或隱藏側邊欄")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onHelp) { Label("使用說明", systemImage: "questionmark.circle") }
                    .help("開啟使用說明")
            }
        }
        .frame(minWidth: 730, minHeight: 600)
    }
}
