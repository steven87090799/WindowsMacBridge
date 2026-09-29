import SwiftUI
import BridgeCore
import InputSourceSupport
import BridgePlatform

enum SettingsPage: String, CaseIterable {
    case general = "一般與權限"
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

    private var general: some View {
        Form {
            if !controller.status.accessibility {
                Section("首次啟用：核准鍵盤權限") {
                    Text("1. 將 WindowsMacBridge 拖到「應用程式」，並從那裡開啟。")
                    Text("2. 按下方按鈕，在「輔助使用」開啟 WindowsMacBridge。")
                    Button("開啟輔助使用設定") { controller.requestAccessibility(); controller.openPermissions() }
                    explanation("快捷鍵預設已開啟；授權後自動開始，不需要執行安裝指令或安裝 Driver。macOS 權限只能由你核准；更新後若系統再次要求，請核准目前版本。")
                }
            }
            Section("WindowsMacBridge · \(AppBuildInfo.current.versionLabel) Preview") {
                Text(controller.summary).font(.headline).textSelection(.enabled)
                explanation("新安裝已啟用 Windows 快捷鍵：本機 Ctrl+C／X／V 會轉成複製／剪下／貼上。Codex 預設適用聊天與文字輸入；Terminal、其他 IDE、遠端桌面、VM 和遊戲保留原按鍵。")
                HStack {
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
                explanation("本機自動翻譯；Terminal、IDE、Remote／VM／Game 依 App 規則保留原按鍵。")
                DisclosureGroup("進階：輸入方式與指定鍵盤") {
                    Picker("輸入方式", selection: Binding(get: { controller.settings.inputBackend }, set: { controller.setInputBackend($0) })) {
                        ForEach(InputBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    explanation("EventTap 是預設：授權後即可使用快捷鍵，適用目前的外接鍵盤，不需安裝 helper 或 Driver。HID 是進階測試方式：可交換 Fn／Control、Option／Command 與亮度鍵，但需另外安裝並核准 Driver，只支援指定鍵盤。切換方式時會同時選擇對應鍵盤範圍。")
                    Picker("鍵盤範圍", selection: Binding(get: { controller.settings.keyboardScope }, set: { controller.setKeyboardScope($0) })) {
                        ForEach(KeyboardScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    explanation("預設「所有鍵盤」，包含 USB、Bluetooth 與內建鍵盤。EventTap 無法只指定某一把鍵盤；選內建／Apple 範圍時必須使用 HID，否則停止翻譯。HID 目前只接受支援的內建鍵盤或 Apple 1452/834，不包含所有 Apple 鍵盤。")
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
                    explanation("一般 DMG 只包含 App。Fn／Control、Option／Command 等硬體鍵位交換仍需另用進階 HID 整合包安裝 Driver；拖曳安裝的快捷鍵模式不包含這些硬體功能。")
                }
                Toggle("Finder 檔案快捷鍵加強", isOn: Binding(get: { controller.settings.finderEnabled }, set: { controller.setFinderEnabled($0) }))
                explanation("預設關閉。開啟後，確認焦點在檔案列表才提供開啟、改名及 Ctrl+X → Ctrl+V 移動；文字框仍使用文字操作。剪下標記在剪貼簿更新、切換 App、暫停或 5 分鐘後失效；程式無法確認 Finder 是否真的移動成功。")
                HStack {
                    Image(systemName: controller.finderExtensionEnabled ? "checkmark.square.fill" : "square")
                    Text("Finder 路徑選單擴充功能")
                    Spacer()
                    if !controller.finderExtensionEnabled {
                        Button("開啟設定") { controller.openFinderExtensionSettings() }
                    }
                }
                explanation("右鍵路徑選單由 App 內的 Finder Sync 擴充功能提供。首次安裝後請在「一般 → 登入項目與擴充功能 → Finder」啟用 WindowsMacBridge Finder；此開關關閉時選單不顯示。")
                Toggle("Finder Shift+Delete 永久刪除", isOn: Binding(get: { controller.settings.finderPermanentDeleteEnabled }, set: { controller.setFinderPermanentDeleteEnabled($0) }))
                    .disabled(!controller.settings.finderEnabled)
                explanation("預設關閉；每次執行前另行確認。")
                Toggle("Windows 文字游標操作", isOn: Binding(get: { controller.settings.textNavigationEnabled }, set: { controller.setTextNavigationEnabled($0) }))
                explanation("Ctrl+方向鍵按單字移動、Home／End 到行首行尾、Ctrl+Home／End 到文件邊界；Shift 組合選取。預設開啟，以維持舊版 Ctrl 文字操作。")
                Toggle("Alt+F4 關閉目前視窗", isOn: Binding(get: { controller.settings.altF4Enabled }, set: { controller.setAltF4Enabled($0) }))
                Toggle("最後一個視窗改為退出 App", isOn: Binding(get: { controller.settings.altF4QuitLastWindow }, set: { controller.setAltF4QuitLastWindow($0) }))
                    .disabled(!controller.settings.altF4Enabled)
                explanation("使用 App 原生關閉／退出快捷鍵；未儲存文件仍由 App 自己確認。")
                Toggle("Alt+Tab 逐視窗切換", isOn: Binding(get: { controller.settings.windowSwitcherEnabled }, set: { controller.setWindowSwitcherEnabled($0) }))
                explanation("只在 Default macOS Profile 攔截；按住 Alt 用 Tab／Shift+Tab 選擇，放開 Alt 切換。顯示 App 圖示與視窗名稱，包含最小化視窗。")
                Toggle("顯示視窗縮圖（需螢幕錄製權限）", isOn: Binding(get: { controller.settings.windowThumbnailsEnabled }, set: { controller.setWindowThumbnailsEnabled($0) }))
                    .disabled(!controller.settings.windowSwitcherEnabled)
                explanation("逐視窗切換、視窗縮圖、Alt+F4 與新增 Finder／文字鍵位使用 EventTap；進階 HID 後端保留原有實體鍵位規則。")
            }
            Section("截圖") {
                Toggle("截圖自動複製（⇧⌘4）", isOn: Binding(
                    get: { controller.settings.screenshotAutoCopy },
                    set: { controller.setScreenshotAutoCopy($0) }))
                explanation("預設開啟。仍可框選，截圖照常存到 macOS 指定位置，完成時也複製圖片供 ⌘V 貼上；Esc 取消時不改剪貼簿。關閉會移除截圖攔截。")
                LabeledContent("截圖狀態", value: controller.screenshotStatus.lastResult)
                if let issue = controller.screenshotStatus.issue { Text(issue).foregroundStyle(.orange) }
                explanation("啟用時立即檢查，之後每 30 天檢查與修復。此功能需要輔助使用與登入啟動；macOS 若要求核准登入項目或權限，請在系統設定完成。")
            }
            Section("登入時啟動") {
                Toggle("登入時啟動 WindowsMacBridge", isOn: Binding(get: { controller.sourceStatus.loginRegistered }, set: { controller.inputSources.setLoginEnabled($0) }))
                    .disabled(controller.settings.screenshotAutoCopy)
                explanation("新安裝因截圖自動複製預設開啟，會註冊登入啟動，以便重新登入後繼續生效；關閉截圖功能時，只有由截圖功能新增的登入註冊會被移除。")
                LabeledContent("系統登入項目狀態", value: controller.sourceStatus.loginStatus)
                Button("開啟登入項目設定") { controller.inputSources.openLoginSettings() }
                explanation("若顯示待核准或啟動失敗，到系統設定檢查 WindowsMacBridge 是否被允許啟動。")
                if let issue = controller.sourceStatus.loginIssue { Text(issue).foregroundStyle(.orange) }
            }
            Section("鍵盤權限") {
                HStack { Image(systemName: controller.status.accessibility ? "checkmark.square.fill" : "square"); Text("輔助使用"); Spacer(); if !controller.status.accessibility { Button("開啟設定") { controller.openPermissions() } } }
                explanation("允許程式攔截快捷鍵及操作 App。未授權時不進行翻譯；第一次下載不能替你自動開啟這項 macOS 權限。")
                HStack { Image(systemName: controller.status.postAccess ? "checkmark.square.fill" : "square"); Text("事件輸出"); Spacer(); if !controller.status.postAccess { Button("開啟設定") { controller.openPermissions() } } }
                explanation("表示程式能否送出翻譯後的按鍵，通常隨輔助使用授權開啟。若不可用，先確認授權的是正在執行的新版 App。")
                HStack { Image(systemName: controller.status.listenAccess ? "checkmark.square.fill" : "square"); Text("輸入監控"); Spacer(); if !controller.status.listenAccess { Button("開啟設定") { controller.openInputMonitoring() } } }
                if controller.settings.windowThumbnailsEnabled {
                    HStack { Image(systemName: controller.screenRecordingGranted ? "checkmark.square.fill" : "square"); Text("螢幕錄製（視窗縮圖）"); Spacer(); if !controller.screenRecordingGranted { Button("開啟設定") { controller.openScreenRecording() } } }
                }
                explanation("用於接收鍵盤事件。EventTap 能否建立也依系統授權而定；HID helper 需要自己的輸入監控權限。唯音守護本身不需要鍵盤權限。")
                HStack {
                    Button("要求輔助使用") { controller.requestAccessibility() }.help("顯示 macOS 的輔助使用授權提示。")
                    Button("開啟權限設定") { controller.openPermissions() }.help("開啟系統設定 → 隱私權與安全性 → 輔助使用。")
                    Button("要求 App 輸入監控") { controller.requestListening() }.help("向 macOS 要求此 App 的輸入監控權限。")
                }
                explanation("按第一個按鈕要求授權；第二個直接開啟系統設定；第三個用於需要輸入監控的情況。更新後若顯示已核准卻不能翻譯，重新加入目前版本並重啟 App。")
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
    }

    private var inputSources: some View {
        Form {
            Section("唯音繁體／ABC") {
                Text(controller.sourceStatus.summary).font(.headline)
                Toggle("啟用輸入法守護", isOn: Binding(get: { controller.sourceStatus.enabled }, set: { controller.inputSources.setEnabled($0) }))
                explanation("預設關閉，不會改變你原本的輸入法。開啟後優先維持唯音繁體；手動切到 ABC 會維持英文，直到下次切換、重新啟用或重啟 App。唯音輸入法本體需另行安裝。")
                LabeledContent("目前來源", value: controller.sourceStatus.current)
                HStack {
                    Button("唯音繁體") { controller.inputSources.select(.vChewing) }
                    Button("ABC") { controller.inputSources.select(.abc) }
                    Button("重新偵測") { controller.inputSources.rediscover() }
                }.disabled(controller.sourceStatus.suspension != nil)
                explanation("前兩個按鈕立即切換輸入法；「重新偵測」用於剛安裝唯音或新增 ABC 之後。Remote、VM、Game、Disabled 或暫停期間不切換；Secure Input 期間延後切換。")
                if controller.sourceStatus.suspension == .legacyApp {
                    Button("結束舊版 VChewingGuard") { controller.inputSources.quitLegacyApp() }
                    explanation("舊版與本程式不能同時守護輸入法；此按鈕正常結束舊版，之後請在登入項目停用舊版。")
                }
                if let issue = controller.sourceStatus.issue { Text(issue).foregroundStyle(.orange).textSelection(.enabled) }
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
            Section("守護等待時間") {
                Stepper("修正延遲：\(controller.sourceStatus.debounceMilliseconds) ms", value: Binding(get: { controller.sourceStatus.debounceMilliseconds }, set: { controller.inputSources.setDebounce($0) }), in: 200...1200, step: 50)
                explanation("預設 400 ms，範圍 200–1200 ms。輸入來源變化後等待多久才重新確認／修正；較短反應快，較長可減少與 App 切換輸入法互相干擾。只影響守護，不增加鍵盤翻譯延遲。")
                Stepper("啟動等待：\(controller.sourceStatus.startupDelayMilliseconds) ms", value: Binding(get: { controller.sourceStatus.startupDelayMilliseconds }, set: { controller.inputSources.setStartupDelay($0) }), in: 0...5000, step: 250)
                explanation("預設 1500 ms，範圍 0–5000 ms。App 啟動後先等待輸入法服務準備，再開始守護。登入時來源偵測不穩，可增加等待；Windows 快捷鍵不受此值影響。")
            }
            Section("舊版整合與來源診斷") {
                Button("匯入舊版 VChewingGuard 偏好") { controller.inputSources.importLegacyPreferences() }.disabled(!controller.sourceStatus.canImportLegacy)
                explanation("只匯入延遲與快捷鍵組合；不匯入啟用狀態、登入項目或歷史紀錄。找不到有效舊設定時按鈕停用。匯入後仍由你決定是否啟用守護。")
                if let message = controller.sourceStatus.migrationMessage { Text(message) }
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
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App 規則").font(.title2)
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
        case .remoteWindows: "讓遠端 Client 收到原按鍵，停止本機翻譯、系統動作與輸入法守護；不判斷是否已連線，也不替 Client 設定轉送。"
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
                LabeledContent("逐視窗 Alt+Tab", value: controller.settings.windowSwitcherEnabled ? (controller.status.tapActive ? "啟用" : "等待 Event Tap") : "關閉")
                LabeledContent("Finder Mode／右鍵擴充", value: "\(controller.settings.finderEnabled ? "啟用" : "關閉")／\(controller.finderExtensionEnabled ? "已核准" : "待核准")")
                LabeledContent("文字游標／Alt+F4", value: "\(controller.settings.textNavigationEnabled ? "啟用" : "關閉")／\(controller.settings.altF4Enabled ? "啟用" : "關閉")")
                if controller.settings.windowThumbnailsEnabled {
                    LabeledContent("視窗縮圖螢幕錄製", value: controller.screenRecordingGranted ? "已授權" : "待授權")
                }
                LabeledContent("截圖 Event Tap", value: controller.screenshotStatus.tapActive ? "Active" : "Inactive")
                LabeledContent("截圖最近結果", value: controller.screenshotStatus.lastResult)
                Text(controller.screenshotLogPath).font(.caption).textSelection(.enabled)
                if let issue = controller.screenshotStatus.issue { Text(issue).foregroundStyle(.orange) }
                explanation("EventTap 模式要看到 Active 才能攔截快捷鍵。HID 模式不使用 EventTap，請回一般頁查看 Helper／Driver 與接管數。")
                LabeledContent("Secure Input", value: controller.status.secureInput ? "ON — 已停止翻譯" : "OFF")
                explanation("macOS 的密碼或安全輸入環境啟用時，程式尊重安全邊界並停止翻譯；離開後等待按鍵放開再恢復。")
                LabeledContent("鍵盤範圍", value: controller.settings.keyboardScope.title)
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
