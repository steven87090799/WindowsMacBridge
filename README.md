# WindowsMacBridge

Windows 快捷鍵相容層與唯音／ABC 輸入法輔助，整合成一個 macOS Menu Bar App。**0.5.7 拖曳安裝個人測試版。** macOS 14+、Apple Silicon；預設 CGEventTap 快捷鍵，進階 HID 後端仍待裝置驗收。

主專案是這個 repository；`vchewing-input-helper` 已移入 `InputSourceCore` 與 `InputSourceSupport`，不需同時執行兩個 App。[整合與遷移](Docs/ProjectIntegration.md)。

## 0.5.7 快速開始

新安裝預設啟用 Windows 快捷鍵、EventTap／所有鍵盤、底層 ABC／U.S. 的中文／唯音快捷鍵、截圖自動複製，以及 Codex 的聊天／文字 Profile。Terminal、其他 IDE、Remote、VM、Game 保留原按鍵；Finder 加強、唯音守護及切換快捷鍵預設關閉。截圖功能會註冊登入啟動，仍可能需要 macOS 核准。更新保留已存設定，可從一般頁按「套用建議預設」。

### 授權清單

開啟設定時先顯示獨立「授權」頁，以簡潔清單列出輔助使用、事件輸出、App 輸入監控、螢幕錄製、Finder 擴充功能及登入啟動。**綠色勾勾表示已取得／啟用，紅色叉叉表示尚未取得／啟用**，每個缺少項目都有可單獨點擊、Tab 選取及 VoiceOver 操作的「前往開啟」按鈕，直接進入對應 macOS 設定。螢幕錄製明確標為視窗縮圖的選用權限；使用 HID 時另外顯示 helper 的輸入監控。

狀態依目前版本的原生 API 檢查結果顯示，不把系統清單裡的舊開關當成已授權。App 啟動、打開設定、回到前景或按「重新檢查」時更新；鍵盤權限變更只觸發一次原生重新查驗，沒有新增輪詢計時器，也不在 SwiftUI 重繪時反覆查詢螢幕錄製權限。可用 `WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --diagnose-permissions` 取得只讀狀態報告，不會提出授權要求或啟動截圖。命令列啟動可能沿用終端機的 TCC 身分，App 的實際授權請以執行中 App 的授權頁為準。唯音守護直接使用本版本設定；舊版助手的程序偵測、避讓、結束及偏好匯入已移除。

0.5.4 起的「前往開啟」只跳到 macOS 設定，不提出隱含授權要求或註冊登入項目；按下不會得到綠勾。回到 App 或按「重新檢查」後，必須由當前 App 的只讀原生檢查確認才顯示綠勾，背景引擎快照不會覆蓋此結果。取消／拒絕仍為紅叉。macOS 若提示「結束並重新打開」才能套用權限變更，請依系統提示重啟；App 不讀取 TCC 資料庫或系統設定 UI 來推測權限。

### 輸入法手動選擇、暫停與統計

從 macOS 狀態欄或系統快捷鍵切換輸入法後，App 立即保留目前選擇並取消待處理的自動修正、重試及 Secure Input 切換意圖。ABC 和第三方輸入法都適用；重新啟用守護、重新偵測、喚醒及重啟 App 也採用當前來源。只有明確使用 WindowsMacBridge 的來源按鈕或切換快捷鍵，才建立新的切換請求。TIS 通知無法判斷是使用者、系統還是另一個 App 發起，因此所有非本程式確認的切換都保守保留，不讀取鍵盤文字來猜測意圖。

「輸入法 → 暫停自動偵測」可選 **5／15／30 分鐘、1 小時、直到手動恢復**，Menu Bar 也提供相同選項。此項只暫停輸入法自動修正，Windows 快捷鍵與既有 Profile 規則維持原設定。暫停截止時間和選項持久保存；使用一次性到期工作，沒有倒數輪詢。更新、重啟或睡眠不延長截止時間，到期或恢復後仍保持目前輸入法。

「輸入法 → 輸入法統計」顯示自動修正成功、程式切回唯音、保留來源切換、失敗、Secure Input 等待、最後成功時間與近期恢復紀錄。首次執行 0.5.3 時，只從舊版 `com.local.VChewingGuard` 的六個 `diagnostics.*` 統計欄位接續資料：計數與本版本相加、成功時間取最新、恢復紀錄合併去重並保留最近 20 筆；匯入完成標記避免重啟重複累加。不存在或損壞的舊資料會略過，現有設定與統計保留。這不會恢復舊版程序偵測或匯入舊版偏好。記憶體 Resident／Physical footprint 只在開啟此頁、按重新整理或讀取診斷時量測，不持續採樣。

### Windows 視窗、Finder 與文字操作

一般設定提供獨立開關：逐視窗 Alt+Tab、視窗縮圖、Finder 檔案操作、Finder 永久刪除、Windows 文字游標、Alt+F4、以及 Alt+F4 最後視窗退出 App。既有文字游標翻譯預設保持開啟；新的 Alt+Tab、Finder、Alt+F4 與永久刪除預設關閉。設定 schema v2 會讀取 v1 資料，保留原先的 App Profile、後端、Finder、截圖與輸入法選擇。

- Alt+Tab 在 EventTap 的 Default macOS Profile 中列出每個視窗的 App 圖示和標題，包含最小化視窗；Alt+Shift+Tab 反向，放開 Alt 才啟用。啟用後以 Accessibility 視窗焦點通知維護 MRU，首次啟用時未觀察到的舊歷史以視窗目前的前後順序補足。選配縮圖在開啟且取得螢幕錄製權限後，才使用 ScreenCaptureKit 按需擷取最多 12 個視窗。無權限時仍可用圖示和標題切換。
- Finder Mode 的 Ctrl+X／Ctrl+V 透過 Finder 原生複製與 `⌥⌘V` 移動；Enter、F2、Delete、Backspace、Ctrl+Shift+N、Ctrl+L 分別開啟、改名、移到垃圾桶、上一層、新增資料夾、前往資料夾。Shift+Delete 必須另行啟用，每次顯示確認，再交給 Finder 處理。文字欄位及未知焦點採保守處理。
- Finder 右鍵路徑選單由內含的 Finder Sync 擴充功能提供，使用 Finder 的 selected/targeted URL。可複製目前資料夾或選取項目的 POSIX 路徑；「顯示目前資料夾路徑」子選單優先顯示所選項目的完整路徑，並提供「複製此路徑」。只有按下複製才寫入剪貼簿。首次安裝請到「系統設定 → 一般 → 登入項目與擴充功能 → Finder」啟用 WindowsMacBridge Finder；Finder Mode 關閉時選單不顯示。
- Windows 文字游標提供 Ctrl+左右方向鍵按單字移動、Ctrl+Backspace／Delete 按單字刪除、Home／End 行首行尾、Ctrl+Home／End 文件首尾，並支援 Shift 選取組合。Alt+F4 發出 App 原生 `⌘W`；選配最後一個主要視窗時發出 `⌘Q`，保留 App 的未儲存內容確認。

這些新動作只在本機 Default macOS Profile 啟用；Terminal、IDE、Remote、VM、Game 維持原樣通過。鍵盤 callback 只處理有界狀態並將 AX、Finder、AppKit 工作送到最多 16 筆的動作佇列。視窗 MRU 用通知更新，縮圖只在顯示切換器時擷取，沒有新增加的長期輪詢。HID 後端保留既有實體鍵位交換語意；新視窗切換器只適用 EventTap。授權頁顯示實際取得的權限，缺少時可直接開啟對應系統設定，仍須由使用者在 macOS 核准。

0.5.5 修正 Finder 選單的設定同步。macOS 15+ 會拒絕未經 provisioning 驗證的免費簽章擴充功能讀取 App Group；因此改用原生 DistributedNotificationCenter，僅傳送版本化的開／關字串，userInfo 為 nil，沒有檔案路徑或剪貼簿資料。App 啟動／開關改動與擴充功能的初始化／資料夾／選單事件才交換狀態，沒有背景輪詢；主設定照常持久保存，App 未執行時不顯示選單。擴充功能維持 App Sandbox。依據 [Apple 的 App Group 存取規則](https://developer.apple.com/documentation/xcode/accessing-app-group-containers) 與 [沙盒通知 API](https://developer.apple.com/documentation/foundation/distributednotificationcenter/post%28name%3Aobject%3Auserinfo%3A%29)。

## 截圖自動複製

「一般 → 截圖」的開關預設開啟；舊設定沒有此欄位時也視為開啟，使用者明確關閉的選擇會持久保存，套用建議預設也不會重設。開啟後，`Shift+Win+S`（Win 鍵在 macOS 對應 Command，即 `⇧⌘S`）進入 macOS 的互動框選（Esc 取消）；完成時圖片存到系統截圖指定的資料夾，並以 PNG／TIFF 圖片格式寫入剪貼簿，可立即按 `⌘V`。會盡量沿用 macOS 截圖的儲存位置與格式；不支援的格式採 PNG，指定資料夾不可寫時改存桌面。原本的 `⇧⌘4` 永遠交由 macOS 處理。關閉開關會移除專屬 Event Tap，不改系統快捷鍵設定，也不使用 Automator。

此功能使用 `/usr/sbin/screencapture -i -s` 啟動原生選取截圖。開啟時會立即檢查可執行檔、儲存位置、輔助使用權限及攔截狀態；往後每 30 天用一次性計時器檢查，遇到 tap 停用、session 恢復或權限恢復也會嘗試修復。診斷寫入 `~/Library/Logs/WindowsMacBridge/Screenshot.log`，只記錄接收此快捷鍵、狀態、錯誤及儲存路徑，不記錄圖片內容或普通按鍵。Esc 取消不動剪貼簿；若儲存成功但複製失敗，圖片仍留在磁碟，設定頁會顯示錯誤。

`Ctrl+Shift+S` 不會觸發截圖，仍依 App Profile 翻譯為另存新檔或原樣通過。0.5.7 修正 Windows 翻譯先將此組合改成 `⌘⇧S`，再被另一個 Event Tap 誤認成 Win 截圖的問題：截圖 Tap 位於 session head，Windows 翻譯位於 session tail，先比對原始修飾鍵；所有本程式產生的事件共用來源標記，截圖也在匹配前排除它們。不依賴 Tap 啟動或恢復順序，不修改 macOS 修飾鍵映射、不增加權限輪詢，也不使用 root HID Tap。

為了重新登入與開機後繼續生效，開啟時會註冊 App 的 macOS 登入項目；若 macOS 顯示待核准，需到系統設定核准。關閉時只移除由此功能新增的登入註冊，原本手動開啟的登入項目保留。App 必須持續執行且已獲得所需權限；更新後若 macOS 要求重新授權，需再次核准。離線單元測試無法驗證實機截圖 UI、螢幕錄製權限提示、實際儲存與貼上。

App 改用黑色鍵盤／雙向箭頭圖示，Menu Bar 不再顯示文字；暫停以雙直線表示。所有設定提供可見說明，另附 [完整操作說明](Resources/UserGuide.md)。設定視窗關閉會釋放 SwiftUI 內容，狀態沒變時不重新發布快照。

「診斷 → 版本與編譯資訊」及 Menu Bar 顯示版本與 Build；診斷頁另顯示 UTC 編譯時間、完整 Git commit、原始碼狀態與 Bundle ID，可複製以便回報。`WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --version` 也輸出相同資訊。這些欄位在建置時寫入已簽章 App 的 Info.plist；發行包應由乾淨的 Git commit 建置，確認狀態為 `clean` 且 commit 對應發行 tag。

開啟 DMG，將 App 拖進 Applications，再開啟並授予輔助使用，即可測一般快捷鍵；**一般 EventTap 使用不需 Install.command 或 Driver**。無付費簽章／公證的下載版可能須在系統設定「仍要打開」；更新也可能要重新授權，不能宣稱完全免系統核准。Codex 預設針對不用內建終端機的用法；若要使用終端機，改回 IDE 或移除該規則。

## 進階 HID 整合測試

App 已接上驗證身分的 XPC、指定 IOHIDDevice 擷取與官方 VirtualHID 輸出。下載包包含 App、helper、官方已公證的 Driver 套件、安裝／停止／移除工具。App/helper 仍是未公證的 ad-hoc 開發版，尚待實體鍵盤與遠端驗收，不能宣稱完整替代完成。

- 29 組一般規則、19 組瀏覽器規則、Finder 剪下／移動與系統動作。
- HID 後端只抓取支援的內建或 Apple 1452/834 服務；Fn／左 Control、左右 Option／Command 交換、完整持有的 Alt+Tab、consumer 亮度增加→Enter。
- Terminal／IDE／Remote／VM／Game／Disabled 的 HID 事件原樣通過；保留右 Option+P 與緊急暫停。不同 descriptor、Caps Lock／Globe／IME、Remote Client 仍需逐項驗收。
- 與唯音／ABC 輸入法守護整合；CGEventTap 預覽後端可另選，兩個後端不會同時翻譯。

安裝與實機檢查：[READ-ME-FIRST](Resources/Installer/READ-ME-FIRST.md)。接線、授權與驗收邊界：[HIDIntegration](Docs/HIDIntegration.md)。原始 78 規則與 upstream 研究：[KarabinerReplacement](Docs/KarabinerReplacement.md)。下載／建置不會啟動引擎；HID 需使用者另行安裝及選擇，不能宣稱完整取代 Karabiner。

## 建置與執行

需要 Swift 6 工具鏈（Xcode 或 Command Line Tools）。主程式沒有第三方 Swift 套件；HID helper 使用固定 revision 的官方 C++ VirtualHID SDK。

```sh
bash scripts/test.sh
bash scripts/build-app.sh
bash scripts/package-app-dmg.sh
# 以下僅建置選用的進階 HID 整合包：
bash scripts/build-hid-helper.sh
bash scripts/package-hid-release.sh
open "$(cat build/APP_PATH.txt)"
```

腳本使用 `~/Library/Caches/WindowsMacBridge/` 作建置暫存，避免同步資料夾 FinderInfo 屬性破壞簽章。App 路徑寫入 `build/APP_PATH.txt`；可用 `BRIDGE_BUILD_DIR` 覆寫。Xcode 可直接開啟 `Package.swift`，目前沒有獨立 `.xcodeproj`。

僅診斷，不攔截鍵盤：

```sh
"$(cat build/APP_PATH.txt)/Contents/MacOS/WindowsMacBridge" --self-check
"$(cat build/APP_PATH.txt)/Contents/MacOS/WindowsMacBridge" --diagnose-backend
```

Windows 快捷鍵預設啟用；唯音守護、輸入法切換鍵預設停用。唯音功能使用 TIS 與 Carbon，不需要 Accessibility，且需先安裝唯音。

Windows 翻譯需於 **系統設定 → 隱私權與安全性 → 輔助使用** 授權 `.app`；Input Monitoring 有獨立診斷，不會反覆要求權限。依使用者選擇採免費 ad-hoc 個人測試發行，不申請付費憑證、不公證，也不繞過 macOS 安全核准。

## 保護與限制

- Remote／VM／Game／Disabled 停止本機規則、輸入法守護與切換鍵；HID 的 Terminal／IDE 保留整個實體鍵盤語意；舊 EventTap 預覽仍允許原設定的本機系統快捷鍵。
- 右 Option+P 與緊急 Ctrl+Option+Command+P 是穿透模式中的保留快捷鍵；tap 不可用時請用 Menu Bar。
- Pause 5／15／60 分鐘或至重啟；Secure Input、session/sleep、權限及 timeout 有界恢復。
- Finder 使用 AX role/parent metadata，未知焦點不猜測；Clipboard 只使用 changeCount/types，不讀內容、不讀檔案 URL、不保留歷史。Clipboard 與 Finder IPC 並非原子交易；不能宣稱 move 成功。
- Finder action mailbox 最多 16 筆，請求有期限並綁定前景 PID 與 epoch。完整 down/up 發往目標 PID，private source/marker 防自身循環，沒有全域持續合成 modifier。
- 非 ABC/U.S. ASCII layout 仍原樣通過。選用 IME 模式不表示已可靠知道是否正在組字。
- Remote Profile 只決定不改鍵，不能保證 Client 將 Alt+Tab、Ctrl+Alt+Delete 或 Clipboard 傳至遠端。
- NSWorkspace 與按鍵非原子同步、Finder 焦點競態、IME 組字、各 Client 與真實硬體都須實機驗收。

## 隱私與驗證

外部資源取樣工具可同步記錄主程式、Finder extension 與系統 CPU／swap／壓縮記憶體，CPU 用同一 PID 的累積時間差計算，重啟重新建立基線；RSS 與 physical footprint 分開保存。`installed_*` 欄位是取樣時磁碟上的版本識別，若程序未重啟，不能據此推定它已載入新版。此工具不加入 App 的執行路徑，結束指定期間後自動停止，檔案預設只讓使用者讀寫。以單調時鐘限制時間，系統時間調整不延長採樣。系統總 CPU 是整台 Mac 的觀測值，不能歸因為此 App 的消耗。

```sh
python3 -m unittest discover -s Tests/MonitoringTests -v
python3 scripts/monitor-runtime.py --duration-seconds 10800 --interval-seconds 60 \
  --footprint-every 5 --include-finder --include-system --phase background \
  --output "$HOME/Library/Logs/WindowsMacBridge/resources-$(date -u +%Y%m%dT%H%M%SZ).csv"
```

不讀取 Unicode 輸入、不保存普通 keyDown 序列、不讀既有 Clipboard payload、不網路上傳。啟用截圖自動複製時只將剛儲存的圖片寫入 Clipboard。診斷最多 128 筆、5 分鐘、只在記憶體保存命中的規則和延遲；普通打字不記錄。唯音模組只保留來源切換狀態日誌與計數，最多兩份約 512 KiB。

測試包含原始設定比對、事件配對與 100,000+ 事件壓測、裝置 ledger、Finder metadata state、程序內 AppKit menu 與 NSTextView 的單字移動／刪除及 Shift／Home／End 選取結果。這些不能證明實體鍵盤經 Event Tap 的端到端操作、實機 CPU/RSS、Remote 相容性或完整替代完成。詳見 [2026-09-28 正式上線前驗收](Docs/ReleaseReadiness-2026-09-28.md)、[Validation](Docs/Validation.md) 與 [替代驗收](Docs/KarabinerReplacement.md)。

移植輸入法模組採 MIT，聲明見 [VChewingGuard license](Resources/Licenses/VChewingGuard.txt)。Karabiner 原始碼研究的來源與架構界線記錄於替代文件；下載安裝包包含固定版原廠簽署的獨立 Driver/daemon 套件及 SDK/vendor 授權聲明。
