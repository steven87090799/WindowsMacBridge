import SwiftUI
import BridgeCore
import InputSourceSupport

struct SettingsView: View {
    @ObservedObject var controller: BridgeController
    var body: some View {
        TabView {
            general.tabItem { Label("一般與權限", systemImage: "keyboard") }
            inputSources.tabItem { Label("唯音與輸入法", systemImage: "character.bubble") }
            profiles.tabItem { Label("App 規則", systemImage: "app.badge") }
            diagnostics.tabItem { Label("診斷", systemImage: "waveform.path.ecg") }
        }
        .padding(20)
        .frame(minWidth: 690, minHeight: 530)
    }
    private var general: some View {
        Form {
            Section("WindowsMacBridge — 開發預覽版") {
                Text(controller.summary).font(.headline).textSelection(.enabled)
                Toggle("啟用 Windows 快捷鍵", isOn: Binding(get: { controller.settings.enabled }, set: controller.setEnabled))
                Text("Ctrl+C / X / V / A / Z / Y / S / F / P → macOS 快捷鍵。原生 Command 操作保持不變。")
                Text("Terminal、Remote、VM、Game、IDE 預設原樣通過。Finder 的 Ctrl+X 尚未啟用。Alt+Tab、Home/End 與 Finder 移動流程仍在規劃中。")
                    .foregroundStyle(.secondary)
            }
            Section("登入啟動") {
                Toggle("登入時啟動 WindowsMacBridge", isOn: Binding(
                    get: { controller.sourceStatus.loginRegistered }, set: controller.inputSources.setLoginEnabled))
                LabeledContent("登入項目", value: controller.sourceStatus.loginStatus)
                Button("開啟登入項目設定") { controller.inputSources.openLoginSettings() }
                if let issue = controller.sourceStatus.loginIssue { Text(issue).foregroundStyle(.orange) }
            }
            Section("權限（僅 Windows 快捷鍵需要）") {
                LabeledContent("Accessibility", value: controller.status.accessibility ? "已授權" : "尚未授權")
                LabeledContent("Event posting", value: controller.status.postAccess ? "可用" : "尚未授權")
                LabeledContent("Input monitoring", value: controller.status.listenAccess ? "可用" : "尚未授權／依 tap 能力而定")
                HStack {
                    Button("要求 Accessibility") { controller.requestAccessibility() }
                    Button("開啟系統設定") { controller.openPermissions() }
                    Button("要求輸入監控") { controller.requestListening() }
                }
                Text("系統設定 → 隱私權與安全性 → 輔助使用。若已授權但 tap 建立失敗，再檢查輸入監控。權限不會自動彈出或無限重試。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("輸入來源與暫停") {
                LabeledContent("Input source", value: controller.layoutID)
                Text("此版僅啟用 ABC／U.S. 鍵位；中文輸入法及其他 layout 會原樣通過。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("暫停 5 分鐘") { controller.pause(minutes: 5) }
                    Button("暫停至重啟") { controller.pause(minutes: nil) }
                    Button("恢復／重啟引擎") { controller.resume() }
                }
                Text("暫停同時停止 Windows 翻譯、輸入法守護與輸入法快捷鍵。緊急暫停：Control + Option + Command + P。Tap 失效或 Client 獨占輸入時，請使用 Menu Bar 暫停／結束。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var inputSources: some View {
        Form {
            Section("唯音繁體／ABC") {
                Text(controller.sourceStatus.summary).font(.headline)
                if controller.sourceStatus.suspension == .legacyApp {
                    Button("結束舊版 VChewingGuard") { controller.inputSources.quitLegacyApp() }
                }
                Toggle("啟用輸入法守護", isOn: Binding(
                    get: { controller.sourceStatus.enabled }, set: controller.inputSources.setEnabled))
                Text("啟用後優先維持唯音繁體；切至 ABC 會維持英文，直到下次切換、重新啟用或重啟 App。唯音輸入法需另行安裝。")
                LabeledContent("目前來源", value: controller.sourceStatus.current)
                HStack {
                    Button("唯音繁體") { controller.inputSources.select(.vChewing) }
                    Button("ABC") { controller.inputSources.select(.abc) }
                    Button("重新偵測") { controller.inputSources.rediscover() }
                }.disabled(controller.sourceStatus.suspension != nil)
                if let issue = controller.sourceStatus.issue { Text(issue).foregroundStyle(.orange).textSelection(.enabled) }
                Text("遠端桌面、VM、Game、Disabled Profile 會暫停守護及切換快捷鍵。Secure Input 期間延後切換。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Windows 快捷鍵目前只在 ABC／U.S. 翻譯；唯音組字期間保持原生按鍵。切換為 ABC 後即可使用 Ctrl+C 等功能。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("切換快捷鍵與延遲") {
                Toggle("啟用唯音／ABC 切換快捷鍵", isOn: Binding(
                    get: { controller.sourceStatus.hotkeyEnabled }, set: controller.inputSources.setHotkeyEnabled))
                Picker("快捷鍵", selection: Binding(get: { controller.sourceStatus.preset }, set: controller.inputSources.setPreset)) {
                    ForEach(HotkeyPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("快捷鍵註冊", value: controller.sourceStatus.hotkeyRegistered ? "已註冊" : "未註冊／暫停")
                Stepper("修正延遲：\(controller.sourceStatus.debounceMilliseconds) ms", value: Binding(
                    get: { controller.sourceStatus.debounceMilliseconds }, set: controller.inputSources.setDebounce), in: 200...1200, step: 50)
                Stepper("啟動等待：\(controller.sourceStatus.startupDelayMilliseconds) ms", value: Binding(
                    get: { controller.sourceStatus.startupDelayMilliseconds }, set: controller.inputSources.setStartupDelay), in: 0...5000, step: 250)
            }
            Section("整合與診斷") {
                Button("匯入舊版 VChewingGuard 偏好") { controller.inputSources.importLegacyPreferences() }
                    .disabled(!controller.sourceStatus.canImportLegacy)
                Text("匯入延遲與快捷鍵選擇。請結束舊版 App，並在系統登入項目停用 VChewingGuard；此 App 使用單一登入項目。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = controller.sourceStatus.migrationMessage { Text(message) }
                DisclosureGroup("輸入來源與守護診斷") {
                    Button("更新診斷") { controller.refreshSourceDiagnostics() }
                    Text(controller.sourceStatus.traditional).textSelection(.enabled)
                    Text(controller.sourceStatus.abc).textSelection(.enabled)
                    Text(controller.sourceDiagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(controller.sourceLog).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                }
                Text("守護日誌僅含來源 ID、切換結果與狀態，最多兩個約 512 KiB 檔案；不記錄按鍵或輸入內容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var profiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App → Profile").font(.title2)
            Text("以 bundle ID 判定整個 App，不猜遠端連線或 IDE terminal focus。瀏覽器內遠端桌面請將整個專用瀏覽器設成 Remote。")
                .foregroundStyle(.secondary)
            if let app = controller.targetApp {
                HStack {
                    VStack(alignment: .leading) {
                        Text("最近的 App：\(app.displayName)")
                        Text(app.bundleID).font(.caption).textSelection(.enabled)
                    }
                    Spacer()
                    Menu("指定 Profile") {
                        ForEach(ApplicationMode.allCases, id: \.self) { mode in
                            Button(mode.title) { controller.assign(mode, bundleID: app.bundleID) }
                        }
                    }
                }
            }
            Button("選擇 App…") { controller.chooseApplication() }
            List(controller.settings.overrides.keys.sorted(), id: \.self) { id in
                HStack {
                    Text(id).textSelection(.enabled)
                    Spacer()
                    Picker("Profile", selection: Binding(get: { controller.settings.overrides[id] ?? .disabled },
                                                         set: { controller.assign($0, bundleID: id) })) {
                        ForEach(ApplicationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 245)
                    Button("重設") { controller.removeOverride(id) }
                }
            }
            Text("手動選 Default macOS 會覆寫內建保護。IDE 的內嵌 Terminal 與遠端 Client 請保留 Pass-through。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(controller.context.displayName) · \(controller.context.mode.title)").font(.headline)
            Text(controller.context.bundleID).textSelection(.enabled)
            Text("Remote connection：未偵測；App profile 只決定是否翻譯。")
                .foregroundStyle(.secondary)
            LabeledContent("Event Tap", value: controller.status.tapActive ? "Active" : "Inactive")
            LabeledContent("Secure Input", value: controller.status.secureInput ? "ON — suspend" : "OFF")
            LabeledContent("Processed / translated", value: "\(controller.status.processed) / \(controller.status.translated)")
            LabeledContent("最大觀測處理時間", value: String(format: "%.2f µs", controller.status.maxMicroseconds))
            Text("此時間不含完整 OS／App 延遲，不代表端到端驗收。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("短期規則診斷（5 分鐘，僅記憶體，最多 128 筆）",
                   isOn: Binding(get: { controller.diagnosticsEnabled }, set: controller.setDiagnostics))
            List(controller.status.diagnostics) { record in
                HStack {
                    Text(record.rule)
                    Text(record.application).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f µs", record.microseconds)).monospacedDigit()
                }
            }
            Text("不讀取輸入文字、不讀剪貼簿、不寫按鍵紀錄、不上傳。只顯示命中的內建規則；普通打字與 pass-through 不產生逐鍵診斷。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
}
