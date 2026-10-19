import SwiftUI
import BridgeCore
import InputSourceSupport
import InputSourceCore
import BridgePlatform

enum SettingsPage: String, CaseIterable {
    case permissions = "權限"
    case general = "一般設定"
    case inputSources = "唯音與輸入法"
    case profiles = "App 規則"
    case preview = "規則預覽"
    case remoteCalibration = "遠端校準"
    case performance = "CPU 與記憶體"
    case diagnostics = "診斷"
}

struct SettingsView: View {
    @ObservedObject var controller: BridgeController

    var body: some View {
        GlassSettingsChrome(selection: Binding(get: { controller.settingsPage }, set: { controller.settingsPage = $0 }),
            advanced: controller.settings.isAdvancedModeEnabled,
            isOperating: controller.isOperating, status: controller.summary,
            version: AppBuildInfo.current.versionLabel, onHelp: controller.openUserGuide) {
            Group {
                switch controller.settingsPage {
                case .permissions: permissionList
                case .general: general
                case .inputSources: inputSources
                case .profiles: profiles
                case .preview: ShortcutPreviewView(controller: controller)
                case .remoteCalibration: RemoteCalibrationView(controller: controller)
                case .performance: PerformanceView()
                case .diagnostics: diagnostics
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var permissionList: some View {
        let usesHID = controller.settings.usesHID
        let keyboardNeeded = controller.settings.enabled || controller.settings.screenshotAutoCopy || controller.settings.macBookFnControlSwap
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("授權項目").font(.headline)
                Spacer()
                    Button("重新檢查") { controller.refreshPermissions(userInitiated: true, recheckScreenshotFolder: true) }
            }
            explanation("依序核准輔助功能與輸入監控；需要截圖時再核准螢幕錄製。每列只申請自己的權限，回來後確認通過才顯示綠燈。登入時啟動為選用。")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow("輔助功能（\(KeyboardPermissionRequest.settingsTitle)）",
                                  verification: controller.permissionChecklist.verification(for: [.accessibility, .posting]),
                                  required: keyboardNeeded,
                                  location: "隱私權與安全性 → \(KeyboardPermissionRequest.settingsTitle) → WindowsMacBridge",
                                  detail: controller.keyboardPermissionRestartSuggested ?
                                  "授權尚未完整套用。若已開啟系統開關，請按「重新開啟 App」；重開後會再次確認。" :
                                  "允許按鍵輸出及視窗操作；核准後若尚未變綠，請結束並重新開啟 App。",
                                  disabledLabel: controller.keyboardPermissionRestartSuggested ? "需重新開啟" : "未取得",
                                  actionLabel: controller.keyboardPermissionRestartSuggested ? "重新開啟 App" : "開啟設定") {
                        if controller.keyboardPermissionRestartSuggested { controller.restartForPermissions() }
                        else {
                            controller.requestAccessibility(); controller.openPermissionSettings(.accessibility)
                        }
                    }
                    .disabled(controller.permissionRelaunchPending)
                    if let notice = controller.permissionRelaunchNotice {
                        Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                    permissionRow("輸入監控：WindowsMacBridge",
                                  verification: controller.inputMonitoringVerification,
                                  required: controller.settings.enabled || controller.settings.screenshotAutoCopy,
                                  location: "隱私權與安全性 → 輸入監控 → WindowsMacBridge",
                                  detail: "允許接收鍵盤事件；一般模式與 HID 都使用 WindowsMacBridge 的這一項權限。核准後若 macOS 要求重開 App，依提示完成。",
                                  actionLabel: "開啟設定") {
                        controller.requestListening(); controller.openPermissionSettings(.listening)
                    }
                    if let notice = controller.backgroundInputNotice {
                        Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                    permissionRow("螢幕錄製",
                                  verification: controller.permissionChecklist.verification(for: [.screenRecording]),
                                  required: controller.settings.screenshotAutoCopy,
                                  location: "隱私權與安全性 → 螢幕與系統音訊錄製 → WindowsMacBridge",
                                  detail: "Windows 與 ⌘⇧3／⌘⇧4 的自動複製截圖需要；只在明確使用截圖時申請。",
                                  actionLabel: "開啟設定") {
                        controller.requestScreenRecording()
                        controller.openPermissionSettings(.screenRecording)
                    }
                    permissionRow("登入時啟動",
                                  verification: controller.permissionChecklist.verification(for: [.loginItem]),
                                  required: false,
                                  location: "一般 → 登入項目與延伸功能 → WindowsMacBridge",
                                  detail: "登入後自動啟動，並在需要時還原內建鍵盤設定；只有按本列才提出申請。",
                                  enabledLabel: "已核准", disabledLabel: "未核准") {
                        controller.requestLoginItem()
                    }
                    if controller.settings.isAdvancedModeEnabled {
                    permissionRow("WindowsMacBridge 鍵盤驅動",
                                  verification: controller.driverVerification, required: usesHID,
                                  location: "一般 → 登入項目與延伸功能 → 驅動程式延伸功能 → .Karabiner‑VirtualHIDDevice‑Manager",
                                  detail: "按本列即可申請並開啟驅動設定。系統中的名稱為 .Karabiner‑VirtualHIDDevice‑Manager；開啟該開關，若要求重開機請依提示完成。",
                                  enabledLabel: "已核准／啟用", disabledLabel: "未核准／未啟用",
                                  actionLabel: "開啟設定") {
                        controller.requestDriverActivation()
                    }
                    if let notice = controller.driverApprovalNotice {
                        Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                    }
                }
            }
            HStack {
                Text("WindowsMacBridge \(AppBuildInfo.current.versionLabel)")
                Spacer()
                if let checkedAt = controller.permissionsCheckedAt {
                    Text("最近檢查：\(checkedAt.formatted(date: .omitted, time: .standard))")
                }
            }.font(.caption).foregroundStyle(.secondary)
            if !controller.permissions.keyboardControlGranted {
                explanation("回到此頁會自動檢查。系統不一定會提示重開；若第一項顯示「需重新開啟」，請按該列按鈕。")
            }
        }
        .padding(20)
        .onAppear { controller.refreshPermissions() }
    }

    private func permissionRow(_ title: String, verification: PermissionVerification, required: Bool,
                               location: String, detail: String,
                               enabledLabel: String = "已取得", disabledLabel: String = "未取得",
                               actionLabel: String = "開啟設定",
                               grantedActionLabel: String = "開啟設定",
                               action: @escaping () -> Void) -> some View {
        let granted = verification == .granted
        let color: Color = granted ? .green : (verification == .denied ? .red : .secondary)
        let label = granted ? enabledLabel : (verification == .unchecked ? "未檢查" :
            (verification == .awaitingVerification ? "等待重新檢查" : disabledLabel))
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: granted ? "checkmark.circle.fill" : (verification == .denied ? "xmark.circle.fill" : "questionmark.circle"))
                    .font(.title2).foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).fontWeight(.medium)
                        Text(required ? "必要" : "選用").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    Text("開啟位置：\(location)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Text(label).font(.callout).foregroundStyle(color)
                    Button(granted ? grantedActionLabel : actionLabel, action: action)
                        .bridgeGlassButton()
                        .accessibilityLabel("\(granted ? grantedActionLabel : actionLabel)：\(title)")
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.70),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Keep each action exposed to VoiceOver and keyboard navigation.
        .accessibilityElement(children: .contain)
    }

    private var general: some View {
        Form {
            Section("WindowsMacBridge · \(AppBuildInfo.current.versionLabel)") {
                HStack(spacing: 8) {
                    Circle().fill(controller.isOperating ? Color.green : Color.secondary).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(controller.isOperating ? "運作中" : controller.summary).font(.headline)
                }
                if controller.status.fault != nil { Button("重新啟動引擎") { controller.resume() } }
                Toggle("Windows 模式總開關", isOn: Binding(get: { controller.settings.enabled }, set: { controller.setEnabled($0) }))
                explanation("統一控制 Windows 快捷鍵、Fn／Ctrl 交換、Finder 加強與截圖自動複製。登入啟動與唯音輸入法守護各自獨立。")
                if !controller.settings.enabled {
                    Text("下列功能已暫停；設定保留，開啟總開關後恢復。").font(.caption).foregroundStyle(.secondary)
                }
                Group {
                    explanation("本機 App、Terminal 與 IDE 共用 Windows 相容操作：複製、貼上、復原、儲存、分頁、文字導覽與 Alt+Tab。遠端 Windows 與虛擬機保留 Ctrl 給 Windows 處理。")
                    Toggle("MacBook 鍵盤模式（交換內建 Fn／地球鍵與左 Ctrl）", isOn: Binding(
                        get: { controller.settings.macBookFnControlSwap }, set: { controller.setMacBookFnControlSwap($0) }))
                    if controller.settings.macBookFnControlSwap {
                        Text(controller.macBookKeyboardStatus.summary).font(.caption).foregroundStyle(.secondary)
                        explanation("只交換這臺 MacBook 的內建鍵盤；外接鍵盤不變。關閉或正常退出後還原，切換時請放開所有按鍵。")
                    }
                    Toggle("Finder 檔案操作加強", isOn: Binding(get: { controller.settings.finderEnabled }, set: { controller.setFinderEnabled($0) }))
                    explanation("Ctrl+X → Ctrl+V 移動檔案，F2 改名，Delete 移到垃圾桶。Shift+Delete 交由 Finder 的「立即刪除」確認視窗保護；不需要 Finder 擴充功能。")
                    Toggle("Windows 快捷截圖（截圖後自動複製）", isOn: Binding(get: { controller.settings.screenshotAutoCopy }, set: { controller.setScreenshotAutoCopy($0) }))
                    explanation("Win+Shift+S／PrintScreen 框選，Alt+PrintScreen 擷取視窗，Win+PrintScreen 儲存全螢幕並複製。⌘⇧3／⌘⇧4 也直接複製；第一次擷取可能由 macOS 要求螢幕錄製授權。")
                    if let issue = controller.screenshotStatus.issue {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                        Button("開啟螢幕錄製設定") { controller.openScreenRecording() }
                    }
                    Picker("這臺 Mac 收到的 Windows 鍵", selection: Binding(get: { controller.settings.windowsKeyModifier }, set: { controller.setWindowsKeyModifier($0) })) {
                        Text("Option ⌥").tag(WindowsKeyModifier.option)
                        Text("Command ⌘").tag(WindowsKeyModifier.command)
                    }
                }
                .disabled(!controller.settings.enabled)
                Toggle("開機自動啟動", isOn: Binding(get: { controller.permissions.loginItem }, set: { controller.setLoginEnabled($0) }))
                if let issue = controller.sourceStatus.loginIssue { Text(issue).foregroundStyle(.orange) }
                HStack {
                    Button("輔助功能授權") { controller.settingsPage = .permissions }
                    Button("使用說明") { controller.openUserGuide() }
                    Button("實機驗收步驟") { controller.openAcceptanceGuide() }
                }
            }
            ScreenshotTextCaptureSection(status: controller.screenshotStatus, canCapture: controller.canCaptureScreenshotText,
                featuresEnabled: controller.settings.enabled && controller.settings.screenshotAutoCopy,
                onCapture: controller.captureScreenshotText, onCancel: controller.cancelScreenshot)
            Section {
                DisclosureGroup("進階選項") {
                    Toggle("解鎖進階後端模式（實驗性）", isOn: Binding(get: { controller.settings.isAdvancedModeEnabled }, set: { controller.setAdvancedModeEnabled($0) }))
                    explanation("選配 HID／VirtualHID，可指定實體鍵盤；通用控制及 iPad 仍需實機驗收。一般模式不安裝、不連線這些元件。")
                    if controller.settings.isAdvancedModeEnabled {
                        Picker("輸入後端", selection: Binding(get: { controller.settings.inputBackend }, set: { controller.setInputBackend($0) })) {
                            ForEach(InputBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        HStack {
                            Button("安裝進階背景元件") { controller.installAdvancedBackend() }
                            Button("移除本 App 的背景元件") { controller.uninstallAdvancedBackend() }
                        }
                        explanation("安裝需要管理員驗證；移除只處理 WindowsMacBridge，保留共用 Driver 與 Karabiner。")
                        if let notice = controller.driverApprovalNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                        if controller.settings.usesHID {
                            Text(controller.hidStatus.state)
                            Text("Driver：\(controller.hidStatus.driverReady ? "Ready" : "尚未就緒")；接管鍵盤：\(controller.hidStatus.capturedDevices)")
                            Button("輸入監控與 Driver 授權") { controller.settingsPage = .permissions }
                            Picker("鍵盤範圍", selection: Binding(get: { controller.settings.keyboardScope }, set: { controller.setKeyboardScope($0) })) {
                                ForEach(KeyboardScope.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            ForEach(controller.hidStatus.devices) { device in
                                Picker(device.product.isEmpty ? "鍵盤" : device.product, selection: Binding(
                                    get: { controller.settings.deviceInputs.first { $0.identity == device.identity }?.experience ?? .windows },
                                    set: { controller.setDeviceExperience($0, identity: device.identity) })) {
                                    Text("Windows").tag(DeviceExperience.windows)
                                    Text("Native Mac").tag(DeviceExperience.nativeMac)
                                }
                            }
                        }
                        Toggle("允許 Shift+Delete 永久刪除（保留確認）", isOn: Binding(get: { controller.settings.finderPermanentDeleteEnabled }, set: { controller.setFinderPermanentDeleteEnabled($0) }))
                        Toggle("Ctrl 文字導覽", isOn: Binding(get: { controller.settings.textNavigationEnabled }, set: { controller.setTextNavigationEnabled($0) }))
                        Toggle("Alt+F4 關閉目前視窗", isOn: Binding(get: { controller.settings.altF4Enabled }, set: { controller.setAltF4Enabled($0) }))
                        Toggle("中文／唯音快捷鍵", isOn: Binding(get: { controller.settings.allowIMEShortcuts }, set: { controller.setIMEShortcuts($0) }))
                        Picker("PrintScreen", selection: Binding(get: { controller.settings.printScreenBehavior }, set: { controller.setPrintScreenBehavior($0) })) {
                            ForEach(PrintScreenBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Button("詳細診斷") { controller.settingsPage = .diagnostics }
                    }
                }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
        .onAppear { controller.refreshMacBookKeyboard() }
    }

    private var inputSources: some View {
        Form {
            Section("唯音繁體／ABC") {
                InputSourceStatusLabel(status: controller.sourceStatus)
                Toggle("啟用輸入法守護", isOn: Binding(get: { controller.sourceStatus.enabled }, set: { controller.inputSources.setEnabled($0) }))
                explanation("預設關閉。開啟後維持唯音繁體；如需英文，請按此頁的 ABC 或使用本 App 的切換快捷鍵。守護只記住這兩種明確操作，系統選單或其他程式切換後會回到守護目標。唯音輸入法本體需另行安裝。")
                LabeledContent("目前輸入法", value: controller.sourceStatus.currentName)
                LabeledContent("守護目標", value: controller.sourceStatus.desired == .vChewing ? "唯音繁體" : "ABC（本 App 明確選擇）")
                HStack {
                    Button("唯音繁體") { controller.inputSources.select(.vChewing) }
                    Button("ABC") { controller.inputSources.select(.abc) }
                    Button("重新偵測") { controller.inputSources.rediscover() }
                }.disabled(controller.sourceStatus.suspension != nil)
                explanation("前兩個按鈕立即切換輸入法；「重新偵測」用於剛安裝唯音或新增 ABC 之後。Remote、VM、Game、Disabled 或暫停期間不切換；Secure Input 期間延後切換。")
                if let issue = controller.sourceStatus.issue { Text(issue).foregroundStyle(.orange).textSelection(.enabled) }
            }
            Section("暫停自動偵測") {
                Picker("停止偵測多久", selection: Binding(get: { controller.sourceStatus.pauseDuration }, set: { controller.inputSources.setPauseDuration($0) })) {
                    ForEach(GuardPauseDuration.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                HStack {
                    Button("暫停偵測") { controller.inputSources.pauseDetection(controller.sourceStatus.pauseDuration) }
                    if controller.sourceStatus.detectionPaused {
                        Button("恢復偵測") { controller.inputSources.resumeDetection() }
                    }
                }
                if controller.sourceStatus.detectionPaused {
                    if controller.sourceStatus.detectionPauseIndefinite {
                        Text("已暫停，直到手動恢復").foregroundStyle(.orange)
                    } else if let until = controller.sourceStatus.detectionPauseUntil {
                        Text("已暫停至 \(until.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.orange)
                    }
                } else {
                    Text("目前沒有暫停偵測").foregroundStyle(.secondary)
                }
                explanation("只暫停輸入法自動修正，Windows 快捷鍵照常。到期或按恢復後回到上方守護目標；暫停期間的系統切換不會更改目標。暫停狀態會保存，更新及重啟後仍有效。")
            }
            Section("輸入法切換快捷鍵") {
                Toggle("啟用唯音／ABC 切換快捷鍵", isOn: Binding(get: { controller.sourceStatus.hotkeyEnabled }, set: { controller.inputSources.setHotkeyEnabled($0) }))
                explanation("預設關閉。開啟後按所選組合在唯音繁體與 ABC 之間切換；Remote／VM／Game／Disabled 與暫停時不註冊此快捷鍵。")
                Picker("快捷鍵組合", selection: Binding(get: { controller.sourceStatus.preset }, set: { controller.inputSources.setPreset($0) })) {
                    ForEach(HotkeyPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                explanation("預設 Control+Option+Command+Space。⌃ 是 Control、⌥ 是 Option、⌘ 是 Command、⇧ 是 Shift。若組合與 macOS 或其他 App 衝突，改選另一個；註冊失敗時嘗試保留原來的組合。")
                LabeledContent("快捷鍵註冊", value: controller.sourceStatus.hotkeyRegistered ? "已註冊" : "未註冊／暫停")
                explanation("「已註冊」才表示快捷鍵能使用；未註冊可能是功能未開啟、目前 App 使用穿透，或組合被占用。")
            }
            Section("輸入法統計") {
                let statistics = controller.sourceStatus.statistics
                LabeledContent("自動修正成功", value: "\(statistics.automaticCorrections) 次")
                LabeledContent("程式切回唯音", value: "\(statistics.vChewingRestores) 次")
                LabeledContent("舊版保留來源切換", value: "\(statistics.preservedExternalSelections) 次")
                LabeledContent("切換失敗", value: "\(statistics.failedSelections) 次")
                LabeledContent("Secure Input 等待", value: "\(statistics.secureInputWaits) 次")
                LabeledContent("最後成功切換", value: statistics.lastSuccessfulSelection?.formatted(date: .abbreviated, time: .standard) ?? "尚無")
                if statistics.previousStatisticsImported {
                    Text("已接續舊版唯音助手的統計資料").font(.caption).foregroundStyle(.secondary)
                }
                if !statistics.recentVChewingRestores.isEmpty {
                    Text("最近程式切回唯音").font(.callout)
                    Text(statistics.recentVChewingRestores.suffix(8).reversed().map {
                        $0.formatted(date: .abbreviated, time: .standard)
                    }.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                }
                Button("重新整理統計") { controller.refreshSourceStatistics() }
                explanation("這些是輸入法切換次數，會持久保存；唯音恢復時間最多保留 20 筆，不記錄輸入文字。CPU 與記憶體請至左側專頁查看，只在該頁可見時取樣。")
            }
            Section("守護等待時間") {
                Stepper("修正延遲：\(controller.sourceStatus.debounceMilliseconds) ms", value: Binding(get: { controller.sourceStatus.debounceMilliseconds }, set: { controller.inputSources.setDebounce($0) }), in: 200...1200, step: 50)
                explanation("預設 400 ms，範圍 200–1200 ms。外部切換偏離守護目標後，等待此時間再修正；切換失敗會有限次重試，頻繁衝突時暫時冷卻。")
                Stepper("啟動等待：\(controller.sourceStatus.startupDelayMilliseconds) ms", value: Binding(get: { controller.sourceStatus.startupDelayMilliseconds }, set: { controller.inputSources.setStartupDelay($0) }), in: 0...5000, step: 250)
                explanation("預設 1500 ms，範圍 0–5000 ms。App 啟動後先等待輸入法服務準備，再開始守護。登入時來源偵測不穩，可增加等待；Windows 快捷鍵不受此值影響。")
            }
            Section("輸入來源診斷") {
                DisclosureGroup("輸入來源與守護診斷") {
                    Button("更新診斷") { controller.refreshSourceDiagnostics() }
                    explanation("重新讀取已安裝的輸入來源與最近切換結果，用於排查唯音／ABC 找不到或切換失敗；不會產生鍵盤紀錄。")
                    Text(controller.sourceStatus.traditional).textSelection(.enabled)
                    Text(controller.sourceStatus.abc).textSelection(.enabled)
                    Text(controller.sourceDiagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(controller.sourceLog).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                }
                explanation("守護日誌只含來源 ID、切換結果與狀態；最多兩個約 512 KiB 檔案，不保存輸入文字。")
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
        .onAppear { controller.refreshSourceStatistics() }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            explanation("規則依 App 的 bundle ID 套用到整個 App。本機 App、Terminal 與 IDE 都套用完整 Windows 相容快捷鍵；Terminal 的 Ctrl+C 有選取時複製、沒有選取時中斷；Ctrl+Shift+C 明確中斷。")
            if let app = controller.targetApp {
                HStack {
                    VStack(alignment: .leading) {
                        Text("最近使用：\(app.displayName)")
                        Text(app.bundleID).font(.caption).textSelection(.enabled)
                    }
                    Spacer()
                    Menu("指定 Profile") {
                        ForEach(ApplicationMode.allCases, id: \.self) { mode in
                            Button(mode.title) { controller.assign(mode, bundleID: app.bundleID) }
                        }
                    }.help("立即儲存最近使用 App 的模式；不需重啟。")
                }
            }
            Button("選擇其他 App…") { controller.chooseApplication() }
            explanation("選取 .app 後先加入 Disabled／原樣通過，再用下方選單指定模式。「移除」會刪除自訂規則並恢復內建判定，包含 Codex 的 IDE Windows 操作模式。")
            List(controller.settings.overrides.keys.sorted(), id: \.self) { id in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(id).font(.callout).textSelection(.enabled)
                        Spacer()
                        Picker("Profile", selection: Binding(get: { controller.settings.overrides[id] ?? .disabled }, set: { controller.assign($0, bundleID: id) })) {
                            ForEach(ApplicationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 255)
                        Button("移除") { controller.removeOverride(id) }.help("移除此 App 的自訂規則，恢復內建保護判定。")
                    }
                    Text(profileExplanation(controller.settings.overrides[id] ?? .disabled)).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            DisclosureGroup("各 Profile 的用途") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ApplicationMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.callout.weight(.medium))
                                Text(profileExplanation(mode)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxHeight: 190)
            }
            explanation("瀏覽器中的遠端分頁無法可靠自動辨識；可使用專用瀏覽器並指定 Remote。遠端 Client 的 Alt+Tab／Ctrl+Alt+Delete／剪貼簿轉送能力需在 Client 自己設定。")
        }.padding()
    }

    private func profileExplanation(_ mode: ApplicationMode) -> String {
        switch mode {
        case .macOS: "本機 App 使用完整 Windows 相容快捷鍵：複製、儲存、復原／重做、搜尋、分頁、文字導覽與系統操作。"
        case .terminal: "Terminal 使用完整 Windows 相容快捷鍵；Ctrl+C 有選取文字時複製，沒有選取時中斷命令；Ctrl+Shift+C 明確中斷。"
        case .ide: "IDE 整個 App 共用完整 Windows 相容快捷鍵，包含儲存、復原／重做、搜尋、分頁與文字導覽。"
        case .remoteWindows: "讓遠端 Client 收到原按鍵，停止本機翻譯、系統動作與輸入法守護。Windows 或 Mac 目標都適用；本 App 無法從 Client 的前景程序判斷連線目標，也不替 Client 設定轉送。"
        case .virtualMachine: "讓 VM 接收原按鍵，停止本機翻譯與輸入法切換；VM 是否捕捉 Alt+Tab 由虛擬機軟體控制。"
        case .game: "讓遊戲接收原按鍵，停止本機翻譯及輸入法切換，避免改動遊戲控制。"
        case .disabled: "此 App 不套用任何本機翻譯或輸入法守護，適用未知或希望完全維持原生行為的 App。"
        }
    }

    private var diagnostics: some View {
        Form {
            Section("版本與編譯資訊") {
                LabeledContent("版本與 Build", value: AppBuildInfo.current.versionLabel)
                LabeledContent("編譯時間（UTC）", value: AppBuildInfo.current.buildDateUTC)
                LabeledContent("Git Commit", value: AppBuildInfo.current.gitRevision)
                LabeledContent("原始碼狀態", value: AppBuildInfo.current.sourceState)
                LabeledContent("Bundle ID", value: AppBuildInfo.current.bundleIdentifier)
                Button("複製版本資訊") { AppBuildInfo.current.copyToPasteboard() }
            }
            Section("目前判定") {
                Text("\(controller.context.displayName) · \(controller.context.mode.title)").font(.headline)
                Text(controller.context.bundleID).textSelection(.enabled)
                explanation("這是目前前景 App 與實際套用的模式；Remote 表示按 App 規則穿透，不表示已確認遠端連線。開啟此設定視窗時，WindowsMacBridge 自己會保持穿透。")
                LabeledContent("輸入方式", value: controller.settings.inputBackend.title)
                LabeledContent("Event Tap", value: controller.status.tapActive ? "Active" : "Inactive")
                LabeledContent("Finder Mode／右鍵擴充", value: "\(controller.settings.finderEnabled ? "啟用" : "關閉")／\(controller.finderExtensionEnabled ? "已核准" : "待核准")")
                LabeledContent("文字游標／Alt+F4", value: "\(controller.settings.textNavigationEnabled ? "啟用" : "關閉")／\(controller.settings.altF4Enabled ? "啟用" : "關閉")")
                LabeledContent("截圖 Event Tap", value: controller.screenshotStatus.tapActive ? "Active" : "Inactive")
                LabeledContent("截圖最近結果", value: controller.screenshotStatus.lastResult)
                Text(controller.screenshotLogPath).font(.caption).textSelection(.enabled)
                if let issue = controller.screenshotStatus.issue { Text(issue).foregroundStyle(.orange) }
                explanation("EventTap 模式要看到 Active 才能攔截快捷鍵。HID 模式不使用 EventTap，請回一般頁查看 Helper／Driver 與接管數。")
                LabeledContent("Secure Input", value: controller.status.secureInput ? "ON — 已停止翻譯" : "OFF")
                explanation("macOS 的密碼或安全輸入環境啟用時，程式尊重安全邊界並停止翻譯；離開後等待按鍵放開再恢復。")
                LabeledContent("鍵盤範圍", value: controller.settings.keyboardScope.title)
                LabeledContent("Fn／Ctrl 交換", value: controller.macBookKeyboardStatus.summary)
                if let issue = controller.status.backendIssue { Text(issue).foregroundStyle(.orange) }
                if let rule = controller.hidStatus.lastRule { LabeledContent("HID 最近命中規則", value: rule) }
                if !controller.status.actionStatus.isEmpty { Text(controller.status.actionStatus) }
            }
            Section("處理計數與延遲") {
                LabeledContent("處理事件／翻譯事件", value: "\(controller.status.processed)／\(controller.status.translated)")
                explanation("處理數包含引擎接收到的事件，翻譯數是實際套用規則的事件。數字不含輸入文字；在穿透 App 中增加處理數但沒有翻譯屬正常。")
                LabeledContent("最大觀測處理時間", value: String(format: "%.2f µs", controller.status.maxMicroseconds))
                explanation("只量測引擎 callback 的最大處理時間，1 ms = 1000 µs；不包含完整 macOS／App／遠端網路延遲，也不等於端到端速度。")
                Button("重新整理計數") { controller.refreshEngineStatus() }
                explanation("一般打字不會為了計數喚醒主執行緒；開啟 5 分鐘診斷時即時更新，否則按此或狀態改變時更新。")
            }
            Section("短期規則診斷") {
                Toggle("啟用 5 分鐘診斷", isOn: Binding(get: { controller.diagnosticsEnabled }, set: { controller.setDiagnostics($0) }))
                explanation("預設關閉。開啟後最多 128 筆規則 ID、App 與處理時間只存於記憶體，5 分鐘後自動關閉；關閉時清除。普通打字不會逐鍵記錄。HID 模式只提供計數與最近命中規則。")
                ForEach(controller.status.diagnostics) { record in
                    HStack {
                        Text(record.rule)
                        Text(record.application).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f µs", record.microseconds)).monospacedDigit()
                    }
                }
                explanation("所有鍵盤處理留在本機。不讀取或保存輸入文字、密碼、剪貼簿內容，也不上傳事件；Finder 只讀取剪貼簿版本與類型。")
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
        .onAppear { controller.refreshEngineStatus() }
    }
}
