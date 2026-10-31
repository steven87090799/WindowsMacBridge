import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BridgeCore
import BridgePlatform

// Select the macOS 14 property-wrapper type explicitly. New SDKs also export a
// State macro whose SwiftUIMacros plugin is absent from some CLT toolchains.
private typealias PreviewState<Value> = SwiftUI.State<Value>

struct ShortcutPreviewView: View {
    private let settings: BridgeSettings
    private let applicationIDs: [String]
    private let resolveContext: @MainActor (String, String, String?) -> ApplicationContext
    @PreviewState private var applications: [ApplicationContext] = []
    @PreviewState private var selectedID = "com.apple.Terminal"
    @PreviewState private var mode: ApplicationMode = .terminal
    @PreviewState private var enabled = true
    @PreviewState private var source: ShortcutPreviewSource = .local
    @PreviewState private var key: UInt16 = 8
    @PreviewState private var modifiers: Modifiers = .control
    @PreviewState private var rows: [ShortcutPreviewResult] = []
    @PreviewState private var customResult: ShortcutPreviewResult?

    private var selectedContext: ApplicationContext {
        applications.first { $0.bundleID == selectedID } ?? resolveContext(selectedID, "", nil)
    }
    private var configuration: ShortcutPreviewConfiguration {
        var context = selectedContext; context.mode = mode
        return settings.shortcutPreview(context: context, enabled: enabled, source: source)
    }
    var body: some View {
        Form {
            Section("快捷鍵規則預覽") {
                Text("先選 App 與預覽模式，查看啟用後的預期輸出。此頁使用合成按鍵計算，不會輸出按鍵或儲存 App 規則。")
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("App", selection: $selectedID) {
                        ForEach(applications, id: \.bundleID) { app in Text(app.displayName).tag(app.bundleID) }
                    }
                    Button("選擇 App…", action: chooseApplication)
                }
                LabeledContent("目前儲存的模式", value: resolveContext(selectedID, selectedContext.executablePath, nil).mode.title)
                Picker("預覽模式", selection: $mode) {
                    ForEach(ApplicationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("按鍵來源", selection: $source) {
                    ForEach(ShortcutPreviewSource.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("模擬 Windows 模式總開關開啟", isOn: $enabled)
                if !settings.enabled {
                    Text("目前實際總開關關閉；可以先預覽，確認後再到一般設定啟用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("常用組合") {
                Table(rows) {
                    TableColumn("送到 Mac 的按鍵") { Text(ShortcutPreview.label($0.input)).monospaced() }
                        .width(min: 180, ideal: 210)
                    TableColumn("預期輸出／操作") { Text($0.output).textSelection(.enabled).help($0.output) }
                }.frame(minHeight: 260)
                if mode == .terminal {
                    Text("Ctrl+C 會在實際按下時確認選取範圍；若 App 無法提供選取狀態，僅嘗試複製。Ctrl+Shift+C 可明確中斷命令。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("自選組合") {
                ViewThatFits(in: .horizontal) {
                    customKeyControls
                    VStack(alignment: .leading, spacing: 10) {
                        keyPicker
                        HStack {
                            modifierToggle("Ctrl", .control)
                            modifierToggle("Option (Win)", .option)
                            modifierToggle("Command (Alt)", .command)
                        }
                        HStack {
                            modifierToggle("Shift", .shift)
                            modifierToggle("Fn", .fn)
                        }
                    }
                }
                if let customResult {
                    LabeledContent(ShortcutPreview.label(customResult.input), value: customResult.output)
                        .textSelection(.enabled)
                }
                Text("預覽使用左側修飾鍵與接收 App 的現行規則。實際效果仍依權限、安全輸入、輸入來源與焦點而定；Finder 檔案操作須經焦點及確認保護。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { reloadApplications() }
        .onChange(of: settings.overrides) { _, _ in reloadApplications() }
        .onChange(of: applicationIDs) { _, _ in reloadApplications() }
        .onChange(of: selectedID) { _, _ in mode = selectedContext.mode }
        .onChange(of: configuration, initial: true) { _, value in updateResults(value) }
        .onChange(of: key) { _, _ in updateCustomResult() }
        .onChange(of: modifiers) { _, _ in updateCustomResult() }
    }

    private var keyPicker: some View {
        Picker("按鍵", selection: $key) {
            ForEach(ShortcutPreview.selectableKeys, id: \.self) { Text(ShortcutPreview.keyLabel($0)).tag($0) }
        }.frame(maxWidth: 170)
    }

    private var customKeyControls: some View {
        HStack {
            keyPicker
            modifierToggle("Ctrl", .control)
            modifierToggle("Option (Win)", .option)
            modifierToggle("Command (Alt)", .command)
            modifierToggle("Shift", .shift)
            modifierToggle("Fn", .fn)
        }
    }

    private func modifierToggle(_ title: String, _ flag: Modifiers) -> some View {
        Toggle(title, isOn: Binding(get: { modifiers.contains(flag) }, set: {
            if $0 { modifiers.insert(flag) } else { modifiers.remove(flag) }
        })).toggleStyle(.checkbox)
    }
    private func updateResults(_ value: ShortcutPreviewConfiguration) {
        rows = ShortcutPreview.samples(windowsKey: value.windowsKeyModifier).map {
            ShortcutPreview.evaluate($0, configuration: value)
        }
        updateCustomResult()
    }
    private func updateCustomResult() {
        customResult = ShortcutPreview.evaluate(.init(keyCode: key, modifiers: modifiers), configuration: configuration)
    }
    private func reloadApplications() {
        let identifiers = applicationIDs
        let previous = applications.filter { !identifiers.contains($0.bundleID) }
        applications = identifiers.map { resolveContext($0, "", nil) } + previous
        if !applications.contains(where: { $0.bundleID == selectedID }), let first = applications.first {
            selectedID = first.bundleID
        }
    }
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return }
        let app = resolveContext(identifier, bundle.executableURL?.path ?? "", url.deletingPathExtension().lastPathComponent)
        applications.removeAll { $0.bundleID == identifier }; applications.append(app)
        selectedID = identifier; mode = app.mode
    }
}

extension ShortcutPreviewView {
    init(controller: BridgeController) {
        settings = controller.settings; applicationIDs = controller.previewApplicationIDs
        resolveContext = { controller.previewContext(bundleID: $0, executablePath: $1, displayName: $2) }
    }
    /// Read-only generated fixtures for offscreen layout verification.
    init(settings: BridgeSettings, applications: [ApplicationContext]) {
        self.settings = settings; applicationIDs = applications.map(\.bundleID)
        resolveContext = { id, _, name in
            var value = applications.first { $0.bundleID == id } ?? .init(processID: 1, bundleID: id, mode: .disabled)
            if let name { value.displayName = name }; return value
        }
    }
}
