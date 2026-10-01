import SwiftUI
import BridgeCore
import InputSourceSupport
import InputSourceCore
import BridgePlatform

enum SettingsPage: String, CaseIterable {
    case permissions = "授權"
    case general = "一般"
    case inputSources = "唯音與輸入法"
    case profiles = "App 規則"
    case diagnostics = "診斷"
}

struct SettingsView: View {
    @ObservedObject var controller: BridgeController

    var body: some View {
        // NSTabView's pane path emits CoreUI bundle-lookup faults on macOS 27,
        // including text-only tab items. Keep one page mounted under a native picker.
        VStack(spacing: 16) {
            Picker("設定分類", selection: Binding(get: { controller.settingsPage }, set: { page in
                // Native picker callbacks can arrive during a SwiftUI update on macOS 27.
                // Publish the page replacement after that update finishes.
                DispatchQueue.main.async { controller.settingsPage = page }
            })) {
                ForEach(SettingsPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
            Group {
                switch controller.settingsPage {
                case .permissions: permissionList
                case .general: general
                case .inputSources: inputSources
                case .profiles: profiles
                case .diagnostics: diagnostics
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(minWidth: 730, minHeight: 600)
    }

    private func explanation(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("授權清單").font(.title2.bold())
                Spacer()
                    Button("重新檢查") { controller.refreshPermissions(userInitiated: true) }
            }
            explanation("綠色勾勾表示已取得；紅色叉叉表示尚未取得。按「前往開啟」即可到對應系統設定。")
            ScrollView {
                VStack(spacing: 0) {
                    permissionRow("輔助使用", granted: controller.permissions.accessibility,
                                  detail: "鍵盤翻譯、截圖及視窗操作") {
                        controller.openPermissionSettings(.accessibility)
                    }
                    permissionRow("事件輸出", granted: controller.permissions.posting,
                                  detail: "送出翻譯後的按鍵；與輔助使用共用授權頁") {
                        controller.openPermissionSettings(.posting)
                    }
                    permissionRow("輸入監控", granted: controller.permissions.listening,
                                  detail: "允許此 App 接收鍵盤事件") {
                        controller.openPermissionSettings(.listening)
                    }
                    permissionRow("螢幕錄製", granted: controller.permissions.screenRecording,
                                  detail: "截圖儲存與剪貼簿功能的選用授權") {
                        controller.openPermissionSettings(.screenRecording)
                    }
                    permissionRow("Finder 擴充功能", granted: controller.permissions.finderExtension,
                                  detail: "選用：Finder 右鍵路徑選單", enabledLabel: "已啟用", disabledLabel: "未啟用") {
                        controller.openPermissionSettings(.finderExtension)
                    }
                    permissionRow("登入時啟動", granted: controller.permissions.loginItem,
                                  detail: "重新登入或開機後繼續執行", enabledLabel: "已核准", disabledLabel: "未核准") {
                        controller.openPermissionSettings(.loginItem)
                    }
                    if controller.settings.inputBackend == .deviceHID {
                        permissionRow("HID helper 輸入監控", granted: controller.hidStatus.permissions,
                                      detail: "進階 HID 後端需要 helper 自己的授權") {
                            controller.requestHIDListening(); controller.openInputMonitoring()
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            HStack {
                Text("WindowsMacBridge \(AppBuildInfo.current.versionLabel)")
                Spacer()
                if let checkedAt = controller.permissionsCheckedAt {
                    Text("最近檢查：\(checkedAt.formatted(date: .omitted, time: .standard))")
                }
            }.font(.caption).foregroundStyle(.secondary)
            if !controller.permissions.accessibility {
                explanation("在系統的「輔助使用」或「裝置控制和資料取用」開啟 WindowsMacBridge。若系統開關已開但這裡仍是紅叉，請重新加入 /Applications 裡的目前版本。")
            }
        }
        .onAppear { controller.refreshPermissions() }
    }

    private func permissionRow(_ title: String, granted: Bool, detail: String,
                               enabledLabel: String = "已取得", disabledLabel: String = "未取得",
                               action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2).foregroundStyle(granted ? Color.green : Color.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(granted ? enabledLabel : disabledLabel)
                    .font(.callout).foregroundStyle(granted ? Color.green : Color.red)
                if !granted {
                    Button("前往開啟", action: action)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("前往開啟\(title)")
                }
            }
            .padding(.vertical, 10)
            Divider()
        }
        .padding(.horizontal, 16)
        // Keep each action exposed to VoiceOver and keyboard navigation.
        .accessibilityElement(children: .contain)
    }

    private var general: some View {
        Form {
            Section("WindowsMacBridge · \(AppBuildInfo.current.versionLabel) Preview") {
                Text(controller.summary).font(.headline).textSelection(.enabled)
                explanation("新安裝已啟用 Windows 快捷鍵：本機 Ctrl+C／X／V 會轉成複製／剪下／貼上。Codex 預設適用聊天與文字輸入；Terminal、其他 IDE、遠端桌面、VM 和遊戲保留原按鍵。")
                HStack {
                    Button("授權清單") { controller.settingsPage = .permissions }
                    Button("套用建議預設") {
                        controller.applyRecommendedPreset()
                    }
                    Button("完整操作說明") { controller.openUserGuide() }
                    Button("實機驗收步驟") { controller.openAcceptanceGuide() }
                }
                explanation("「套用建議預設」會啟用快捷鍵及中文／唯音相容、選 EventTap／所有鍵盤、將 Codex 設為 Default macOS，並關閉 Finder 檔案加強。保留其他 App 規則、輸入法及登入設定；下方仍可逐項調整。")
                if let notice = controller.presetNotice { Text(notice).foregroundStyle(.secondary) }
            }
            Section("Windows 快捷鍵") {
                Toggle("啟用 Windows 快捷鍵", isOn: Binding(get: { controller.settings.enabled }, set: { controller.setEnabled($0) }))
                explanation("預設開啟。包含複製、貼上、復原、儲存、尋找、分頁與 Ctrl 文字導覽；關閉後停止 Windows 按鍵翻譯，輸入法守護由自己的開關控制。")
                Picker("這臺 Mac 收到的 Windows 鍵", selection: Binding(
                    get: { controller.settings.windowsKeyModifier },
                    set: { controller.setWindowsKeyModifier($0) })) {
                    Text("Option (⌥)：這把鍵盤的 Win 送出 Option").tag(WindowsKeyModifier.option)
                    Text("Command (⌘)：這把鍵盤的 Win 送出 Command").tag(WindowsKeyModifier.command)
                }
                explanation("Mac mini 預設 Option，MacBook 預設 Command；舊設定缺少此欄時依本機機型選擇。這項選擇讓 Win 專用操作和 Alt+F4／瀏覽器上一頁、下一頁依實際輸入判斷，不交換整把鍵盤；Alt+Tab 交由 macOS 原生按鍵決定。Ctrl 文字操作不受影響。通用控制換用不同來源鍵盤時，EventTap 無法辨識來源，必要時在接收端切換。")
                explanation("本機自動翻譯；Terminal、IDE、Remote／VM／Game 依 App 規則保留原按鍵。")
                DisclosureGroup("進階：輸入方式與指定鍵盤") {
                    Picker("輸入方式", selection: Binding(get: { controller.settings.inputBackend }, set: { controller.setInputBackend($0) })) {
                        ForEach(InputBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    explanation("EventTap 是預設：授權後即可使用快捷鍵。下方 MacBook Fn／Ctrl 交換可用原生 API，不需 Driver。HID 是進階測試方式：只接管指定鍵盤；依 Win 鍵選擇處理 Option／Command，內建鍵盤依下方開關處理 Fn／Ctrl，另支援亮度鍵。需安裝並核准 Driver。")
                    Picker("鍵盤範圍", selection: Binding(get: { controller.settings.keyboardScope }, set: { controller.setKeyboardScope($0) })) {
                        ForEach(KeyboardScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    explanation("預設「所有鍵盤」，包含 USB、Bluetooth 與內建鍵盤。EventTap 無法只指定某一把鍵盤；選內建／Apple 範圍時必須使用 HID，否則停止翻譯。HID 只接管可完整回報支援按鍵的實體 keyboard service；複合滑鼠、虛擬與通用控制服務保持原樣。")
                    explanation("不要同時在 Karabiner 套用相同映射。若系統已交換 Control／Command，程式收到的是交換後的按鍵；請依完整操作說明確認實際結果，再決定是否還原。")
                    if controller.settings.inputBackend == .deviceHID {
                        LabeledContent("Helper 狀態", value: controller.hidStatus.state)
                        LabeledContent("Driver／接管鍵盤數", value: "\(controller.hidStatus.driverReady ? "Ready" : "Not ready")／\(controller.hidStatus.capturedDevices)")
                        explanation("需先執行下載包的 Install.command 並依 macOS 提示核准官方 VirtualHID。Ready 且接管數大於 0 才表示此後端有鍵盤可用；不支援的鍵盤維持原樣。此路徑仍待實體裝置驗收。")
                        Button("在 Finder 顯示 helper") { controller.openHelperLocation() }
                        explanation("手動加入輸入監控時，用此按鈕找到 BridgeHIDHelper.app，再到系統設定的輸入監控清單加入。尚未安裝 helper 時，請先執行 Install.command。")
                        Button("要求 helper 輸入監控權限") { controller.requestHIDListening() }
                        explanation("要求 macOS 允許已安裝的 helper 接收鍵盤；需由你在系統設定核准，按鈕不會自動授權。")
                    }
                    explanation("一般 DMG 包含原生 MacBook Fn／Ctrl 交換；Option／Command 與亮度鍵等進階交換仍需另用 HID 整合包。")
                }
                Toggle("MacBook 內建鍵盤：交換 Fn／地球鍵與左 Ctrl", isOn: Binding(
                    get: { controller.settings.macBookFnControlSwap }, set: { controller.setMacBookFnControlSwap($0) }))
                explanation("MacBook 新安裝預設開啟，Mac mini 預設關閉；舊設定中明確關閉會保留。Fn 變成 Ctrl、原左 Ctrl 變成 Fn；右 Ctrl 及外接鍵盤保持原樣。EventTap 使用內建鍵盤的原生 HID 服務；進階 HID 後端只在其接管的內建鍵盤服務上套用相同交換，不會疊加。退出 App 或關閉時還原；請先放開按鍵再切換。")
                explanation("通用控制：在鍵盤實際所在的 MacBook 開啟。接收端不交換虛擬鍵盤，避免交換兩次；Mac mini 的外接鍵盤操作 MacBook 時仍保持外接排列。兩臺 Mac 的跨機修飾鍵結果需實測。EventTap 的 Fn／Ctrl 原生交換作用於本機內建鍵盤；HID 的 Remote／VM／Game Profile 會釋放鍵盤，維持原生穿透。")
                LabeledContent("MacBook 鍵盤模式", value: controller.macBookKeyboardStatus.summary)
                Button("重新檢查鍵盤模式") { controller.refreshMacBookKeyboard() }
                if let issue = controller.macBookKeyboardStatus.issue { Text(issue).foregroundStyle(.orange) }
                Toggle("Finder 檔案快捷鍵加強", isOn: Binding(get: { controller.settings.finderEnabled }, set: { controller.setFinderEnabled($0) }))
                explanation("預設關閉。開啟後，確認焦點在檔案列表才提供開啟、改名及 Ctrl+X → Ctrl+V 移動；文字框仍使用文字操作。剪下標記保留跨資料夾及路徑導覽；剪貼簿更新、Finder 重新啟動或 5 分鐘後失效；程式無法確認 Finder 是否真的移動成功。")
                explanation("右鍵路徑選單由 App 內的 Finder Sync 擴充功能提供。首次安裝後請在「一般 → 登入項目與擴充功能 → Finder」啟用 WindowsMacBridge Finder；此開關關閉時選單不顯示。")
                Toggle("Finder 亮度增加鍵作為 Enter（HID，預設關閉）", isOn: Binding(get: { controller.settings.finderBrightnessEnterEnabled }, set: { controller.setFinderBrightnessEnterEnabled($0) }))
                    .disabled(!controller.settings.finderEnabled || controller.settings.inputBackend != .deviceHID)
                explanation("僅在 Finder 檔案模式及 HID 接管鍵盤生效；其他 App 保留原 consumer 亮度鍵。")
                Toggle("Finder Shift+Delete 永久刪除", isOn: Binding(get: { controller.settings.finderPermanentDeleteEnabled }, set: { controller.setFinderPermanentDeleteEnabled($0) }))
                    .disabled(!controller.settings.finderEnabled)
                explanation("預設關閉；每次執行前另行確認。")
                Toggle("Windows 文字游標操作", isOn: Binding(get: { controller.settings.textNavigationEnabled }, set: { controller.setTextNavigationEnabled($0) }))
                explanation("Ctrl+方向鍵按單字移動、Home／End 到行首行尾、Ctrl+Home／End 到文件邊界；Shift 組合選取。預設開啟，以維持舊版 Ctrl 文字操作。")
                Toggle("Alt+F4 關閉目前視窗", isOn: Binding(get: { controller.settings.altF4Enabled }, set: { controller.setAltF4Enabled($0) }))
                explanation("透過輔助使用按下目前視窗的關閉按鈕；保留 App 的未儲存提示。不支援 AX 關閉時顯示失敗，避免誤關分頁或整個 App。")
                explanation("Alt+Tab 交由 macOS 原生 App 切換器處理（依鍵盤映射可能顯示為 ⌘Tab）；同一 App 的視窗可用 ⌘` 切換。")
                Toggle("Win+R 開啟 Spotlight 搜尋", isOn: Binding(get: { controller.settings.winRunEnabled }, set: { controller.setWinRunEnabled($0) }))
                Toggle("Win+I 開啟系統設定", isOn: Binding(get: { controller.settings.winSettingsEnabled }, set: { controller.setWinSettingsEnabled($0) }))
                Toggle("Win+Tab 開啟 Mission Control", isOn: Binding(get: { controller.settings.winTaskViewEnabled }, set: { controller.setWinTaskViewEnabled($0) }))
                explanation("這三項預設關閉，各自選用；僅在 Default macOS Profile 生效。Win+R 使用 macOS ⌘Space，Win+Tab 使用 ⌃↑；若你已改過系統快捷鍵，結果會跟隨 macOS 設定。")
                explanation("Alt+F4、Finder、文字及截圖功能共用安全政策；切換後端或暫停會取消尚未完成的操作。")
            }
            Section("截圖") {
                Toggle("截圖自動複製（Shift+Win+S）", isOn: Binding(
                    get: { controller.settings.screenshotAutoCopy },
                    set: { controller.setScreenshotAutoCopy($0) }))
                Picker("PrintScreen", selection: Binding(get: { controller.settings.printScreenBehavior }, set: { controller.setPrintScreenBehavior($0) })) {
                    ForEach(PrintScreenBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                explanation("Win+Shift+S 框選；Alt+PrintScreen 複製目前視窗；Win+PrintScreen 儲存全螢幕並複製；PrintScreen 依上方設定。HID 使用已接管的實體按鍵；EventTap 的 PrintScreen 對應 F13。")
                explanation("使用上方所選的 Windows 鍵位置。若實體 Alt+Shift+S 觸發截圖，代表此處選錯了映射。")
                explanation("框選完成後存檔並複製 PNG 圖片供 ⌘V 貼上。Ctrl+Shift+S 不會觸發截圖。原本的 ⇧⌘4 交由 macOS 處理；Esc 取消時不改剪貼簿。")
                LabeledContent("截圖狀態", value: controller.screenshotStatus.lastResult)
                if let issue = controller.screenshotStatus.issue { Text(issue).foregroundStyle(.orange) }
                explanation("啟用時立即檢查，之後每 30 天檢查與修復。此功能需要輔助使用與登入啟動；macOS 若要求核准登入項目或權限，請在系統設定完成。")
            }
            Section("登入時啟動") {
                Toggle("登入時啟動 WindowsMacBridge", isOn: Binding(get: { controller.sourceStatus.loginRegistered }, set: { controller.inputSources.setLoginEnabled($0) }))
                    .disabled(controller.settings.screenshotAutoCopy || controller.settings.macBookFnControlSwap)
                explanation("截圖自動複製或 MacBook Fn／Ctrl 模式開啟時，會註冊登入啟動。兩者都關閉才移除由這些功能新增的註冊；原先手動開啟的登入項目保留。")
                LabeledContent("系統登入項目狀態", value: controller.sourceStatus.loginStatus)
                Button("開啟登入項目設定") { controller.inputSources.openLoginSettings() }
                explanation("若顯示待核准或啟動失敗，到系統設定檢查 WindowsMacBridge 是否被允許啟動。")
                if let issue = controller.sourceStatus.loginIssue { Text(issue).foregroundStyle(.orange) }
            }
            Section("輸入法相容性") {
                LabeledContent("目前輸入來源", value: controller.layoutID)
                Toggle("中文／唯音輸入法也使用實體鍵位快捷鍵", isOn: Binding(get: { controller.settings.allowIMEShortcuts }, set: { controller.setIMEShortcuts($0) }))
                explanation("預設開啟，底層採 ABC／U.S. 的中文輸入法也可使用 Ctrl 快捷鍵。程式不讀取組字內容；候選選字與組字相容性仍需依 App 確認，遇到衝突可關閉，改成只在 ABC／U.S. 來源翻譯。其他配置維持原樣。")
            }
            Section("暫停與恢復") {
                HStack {
                    Button("暫停 5 分鐘") { controller.pause(minutes: 5) }
                    Button("暫停至重啟") { controller.pause(minutes: nil) }
                    Button("恢復／重啟引擎") { controller.resume() }
                }
                explanation("暫停同時停止 Windows 翻譯與輸入法守護；5 分鐘後自動恢復，或關閉重開 App 才恢復。「恢復」取消暫停、退出穿透並重新嘗試啟動引擎。Menu Bar 也提供 15 分鐘／1 小時。")
                explanation("右 Option+P 切換原樣穿透；Control+Option+Command+P 緊急暫停。Remote／VM／Game 的 HID 模式交回鍵盤後不攔截這些熱鍵，請用 Menu Bar 暫停或結束。暫停圖示是鍵盤內的雙直線。")
            }
        }.formStyle(.grouped)
        .onAppear { controller.refreshMacBookKeyboard() }
    }

    private var inputSources: some View {
        Form {
            Section("唯音繁體／ABC") {
                Text(controller.sourceStatus.summary).font(.headline)
                Toggle("啟用輸入法守護", isOn: Binding(get: { controller.sourceStatus.enabled }, set: { controller.inputSources.setEnabled($0) }))
                explanation("預設關閉。從狀態欄或 macOS 快捷鍵手動切換後會保持；喚醒、恢復或重啟 App 也保留目前輸入法。唯音輸入法本體需另行安裝。")
                LabeledContent("目前輸入法", value: controller.sourceStatus.currentName)
                if controller.sourceStatus.preservedSourceIdentifier != nil {
                    Text("手動切換已保留").foregroundStyle(.green)
                }
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
                explanation("只暫停輸入法自動修正，Windows 快捷鍵照常。到期或按恢復後保持當前輸入法；暫停狀態會保存，更新及重啟後仍有效。")
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
                LabeledContent("保留來源切換", value: "\(statistics.preservedExternalSelections) 次")
                LabeledContent("切換失敗", value: "\(statistics.failedSelections) 次")
                LabeledContent("Secure Input 等待", value: "\(statistics.secureInputWaits) 次")
                LabeledContent("最後成功切換", value: statistics.lastSuccessfulSelection?.formatted(date: .abbreviated, time: .standard) ?? "尚無")
                LabeledContent("記憶體", value: controller.sourceMemoryUsage)
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
                explanation("統計會持久保存，唯音恢復時間最多保留 20 筆。記憶體只在開啟此頁或按重新整理時讀取；不記錄輸入文字。")
            }
            Section("守護等待時間") {
                Stepper("修正延遲：\(controller.sourceStatus.debounceMilliseconds) ms", value: Binding(get: { controller.sourceStatus.debounceMilliseconds }, set: { controller.inputSources.setDebounce($0) }), in: 200...1200, step: 50)
                explanation("預設 400 ms，範圍 200–1200 ms。用於程式自身切換失敗後的有界重試；手動切換會立即保留，不等待這個延遲。")
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
        }.formStyle(.grouped)
        .onAppear { controller.refreshSourceStatistics() }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App 規則").font(.title2)
            Picker("遠端／通用控制輸入角色", selection: Binding(get: { controller.settings.remoteInputProfile }, set: { controller.setRemoteInputProfile($0) })) {
                ForEach(RemoteInputProfile.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            explanation("在接收端明確選擇來源角色。來源端已有 Bridge 時，接收端選原樣通過；Windows 軟體注入到 Mac 請在接收端選 EventTap。傳輸未保留來源資訊時，無法自動可靠辨識或協調兩端。")
            explanation("規則依 App 的 bundle ID 套用到整個 App。Codex 新安裝預設 Default macOS，適合聊天與文字輸入；若使用內建終端機，改成 IDE 或移除規則，避免 Ctrl+C 被當成複製。")
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
            explanation("選取 .app 後先加入 Disabled／原樣通過，再用下方選單指定模式。「移除」會刪除自訂規則並恢復內建判定，包含 Codex 的 IDE 保護。")
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
        case .macOS: "本機翻譯：將 Windows 快捷鍵轉為 macOS 操作；手動指定會覆寫此 App 原本的 Terminal／IDE 等保護。"
        case .terminal: "保留 Unix 的 Ctrl+C／D／Z 等操作。HID 整個鍵盤原樣通過；EventTap 保留 Ctrl 與文字快捷鍵，仍提供部分本機系統動作。"
        case .ide: "保留編輯器、除錯器與內嵌 Terminal 的原生 Ctrl 操作；若只用聊天／文字且需要 Ctrl+C／V，可改為 Default macOS。"
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
        }.formStyle(.grouped)
    }
}
