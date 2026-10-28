# WindowsMacBridge

Apple Silicon、macOS 14+ 的選單列鍵盤工具，整合 Windows 快捷鍵、MacBook 內建 Fn／Ctrl、Finder 操作、截圖與選配唯音／ABC 管理。正式版本 **1.0.2（build 66）**，修正系統應用程式清單包含重複無效 PID 時，背景程式會當機退出的問題。Ctrl+C／X／V／A 共用本機剪貼簿規則，涵蓋系統浮動視窗、Terminal、輸入法與本機 App Profile；截圖縮圖點擊後直接置中並啟用 App 內的圖片預覽視窗。設定側邊欄保留清晰文字與原生液態玻璃切換動畫；包含規則預覽與遠端校準介面（歷史審查：[FinalProductionReview-2026-10-03](Docs/FinalProductionReview-2026-10-03.md)）。

## v1.0.2 正式版（build 66）

- [背景當機的證據、原因與修正](Docs/BackgroundCrash-2026-10-24.md)
- [更新與跨機安裝說明](Docs/ReleaseNotes-1.0.2.md)／[下載 v1.0.2](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.2)

修正重複無效 PID 當機，並加入異常停止後的自動恢復與提示；正常結束不重開，連續失敗有次數限制。恢復程序採事件等待，沒有固定心跳輪詢。

## v1.0.1 正式版（build 64）

- [Apple 螢幕共享／VNC 問題、修正與雙向驗證](Docs/ScreenSharingVNC-2026-10-24.md)
- [更新與安裝說明](Docs/ReleaseNotes-1.0.1.md)／[下載 v1.0.1](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.1)

## v1.0.0 正式版（build 63）

- [本次問題、根因、修改位置、事件證據與後續注意事項](Docs/Build62-FnControl-UniversalControl-Handoff.md)
- [完整實機診斷紀錄](Docs/FnControlDiagnosis-2026-10-23.md)／[修復前後事件節錄](Docs/UCControlEventEvidence-2026-10-23.txt)
- [正式版更新與換機安裝說明](Docs/ReleaseNotes-1.0.0.md)／[下載 v1.0.0 完整 ZIP 或 DMG](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.0)
- [build 63 的修正、資源量測與驗證範圍](Docs/Build62-Review-2026-10-23.md)

535 項自動測試通過。build 62 的前次操作中，使用者已在本次 MacBook 實測內建 Fn+C／X／V／A、左 Ctrl→Fn，以及另一台 Mac 外接鍵盤經通用控制送入的 Ctrl+C／V。其他硬體、舊系統與進階 HID 安裝仍需各自驗收；一般模式不需要另裝 Driver。

## 一般模式與進階模式已分開

預設使用**一般模式**。Windows 快捷鍵、Finder 操作、截圖及內建鍵盤 Fn／Ctrl 交換都能從一般設定開啟；不必先安裝 HID 或 Driver。

| 項目 | 一般模式（預設） | 進階模式（明確選用） |
|---|---|---|
| 輸入後端 | 使用者層 EventTap | 可選 EventTap 或裝置 HID／VirtualHID |
| 鍵盤範圍 | 所有鍵盤；EventTap 無可靠逐裝置 ID | HID 可設定實體鍵盤範圍與偏好 |
| 基本權限 | 輔助功能與輸入監控 | 相同；HID 另驗證背景元件的讀取授權 |
| 截圖 | 另需螢幕錄製；完成直接複製 | 相同 |
| Root Helper／XPC／Driver | 不建立 HID client、不連線、不自動安裝或提權 | 開啟進階選項、選 HID 並明確安裝後才使用 |
| 登入時啟動 | 選用，使用者自行開啟 | 選用 |

一般模式**仍需要正常的鍵盤與截圖授權**；拆開的是 HID／Root／Driver 依賴。權限頁逐項列出所需設定，每次只申請一項，回到 App 後重新讀取原生授權結果。權限綠燈只代表該項授權通過，鍵盤後端也必須實際啟動才能顯示運作中。

切回一般模式會釋放本 App 的 HID 所有權並銷毀連線；舊 HID 確認停止前兩種後端都不翻譯（最多 3 秒）；只有停止回覆、從未擷取或背景元件確定結束才算釋放，XPC 中斷或逾時都保持停用到使用者按「恢復／重啟引擎」。舊 HID 設定不會自動啟用進階模式；已安裝的共用 Karabiner Driver／服務會保留，避免影響其他使用者，不能把它們仍存在誤稱為全機已沒有背景服務。

## 安裝

點兩下DMG，把WindowsMacBridge.app拖進Applications，正常退出舊版後替換。一般模式逐項列出輔助功能、輸入監控、螢幕錄製與選用的登入啟動，回到App由原生API確認各項授權。一般快捷鍵先核准前兩項；截圖另需螢幕錄製。沒有自動Root安裝、HID/XPC連接或Driver提示；登錄啓動需用戶明確開啓。截圖第一次明確使用可能需要ScreenCapture授權。

App使用ad-hoc簽章、尚無Apple公證；更新可能需要重新核准本版App，不能以同名舊授權項視為已通過。不要關閉SIP／Gatekeeper或重設其他App權限。

## 功能與默認

「Windows 模式總開關」統一控制快捷鍵、Fn／Ctrl 交換、Finder 加強與截圖自動複製。關閉時暫停這些功能並保留子項設定；唯音輸入法守護與登入啟動各自獨立。

| 功能 | 一般模式默認 |
|---|---|
| Ctrl複製／貼上／復原／全選／儲存、文字導覽、瀏覽器分頁 | 開 |
| Alt+Tab、Alt+F4 | macOS原生切換／當前窗口關閉，保留未儲存提示 |
| Finder Ctrl+X→V移動、F2、Delete、確認式ShiftDelete | 開；ShiftDelete由Finder原生確認；焦點無法確認時只貼上不搬移；不需FinderSync，根目錄監控已移除 |
| Shift+Option+S、PrintScreen 與 ⌘⇧3／4 | 開；完成直接寫PNG clipboard，取消／舊session不寫入 |
| MacBook Fn／左Ctrl | 關，明確開關只改本機builtIn鍵盤 |
| Windows鍵位置 | Option ⌥；Command ⌘ 對應 Alt，舊版 Command 設定自動遷移 |
| 唯音守護／Carbon切換熱鍵 | 各自關；守護開啟後維持本 App 明確選定的唯音／ABC，預設唯音 |
| Terminal／IDE | 共用完整 Windows 相容規則；Ctrl+C 一律複製，不查詢選取狀態；Terminal 的 Ctrl+Shift+C 中斷命令 |
| Remote viewer／VM／Game | 遠端 Windows／VM 保留 Ctrl 給 Windows 處理；本機 Game／停用延伸規則的 Profile 仍提供 Ctrl+C／X／V／A，其他按鍵通過 |
| HID／VirtualHID／root runtime | 進階選配，默認關 |
| 快捷鍵規則預覽 | 設定 → 規則預覽；使用實際處理器計算，不啟用監聽、不輸出按鍵或更改 App 規則 |
| 遠端來源校準 | 設定 → 遠端校準；明確開始、一次 Ctrl+C、60 秒期限、確認套用與還原 |

一般模式EventTap使用全部鍵盤，沒有可靠逐裝置ID。舊HID選擇不自動解鎖新進階模式，已有App規則、鍵位與明確功能選擇保留。Settings schema 6，損壞設置安全停用。

進階抽屜勾選後才顯示後端、安裝／移除、Driver、裝置偏好與診斷。所有材料封裝在同一App；root模式用root-owned簽章鏡像，不讓root執行用戶可替換的Applications文件。共享官方Karabiner Driver不改簽章名稱、不因切一般或卸載本App的runtime被刪除。支持的Driver版本有checksum／簽章／交易恢復限制，不宣稱任意升級與降級都已驗收。

## Windows 按鍵對應

所有流程統一使用 Option＝Windows Win、Command＝Windows Alt。Shift+Option+S 框選截圖；Option+E 開啟 Finder、Option+L 鎖定，選用的 Option+R／I／Tab 分別開啟搜尋、系統設定與 Mission Control。Command+Tab／F4 對應 Alt+Tab／F4；瀏覽器與 Finder 的 Alt+左右鍵使用 Command+左右鍵。Ctrl+C 等仍輸出 macOS 原生 ⌘C。新安裝、舊設定、快捷鍵預覽、一般 EventTap、HID 與已辨識遠端來源共用此對應。

Windows／VM 的原樣通過保護維持原始輸入；未知來源不猜測鍵位。外部鍵盤若已由系統或其他工具換位，以實際送入的 Option／Command 為準；本 App 不更改外部工具設定。

[完整按鍵對應與驗證記錄](Docs/WindowsKeyMapping-2026-10-28.md)。

## 截圖與儲存位置

Shift+Option+S／PrintScreen、Command+PrintScreen（Alt+PrintScreen）及攔截的 ⌘⇧3／4 使用 App 私有暫存 PNG；擷取成功先複製，再顯示自製「截圖已複製」預覽，不等待 macOS 浮動縮圖存檔。預覽消失或點開的圖片視窗關閉後清除自己的暫存原圖。只有 Option+PrintScreen（Win+PrintScreen）明確保存全螢幕圖片到桌面，檔案不隨預覽關閉刪除。

預覽由 220×160 放大為 320×248，採圓角圖片區與主副文字；macOS 26+ 且建置 SDK 支援時使用 Apple Liquid Glass，較舊版本使用毛玻璃。一般顯示 5 秒，滑鼠移入會保留，移出重新計時；點圖開啟系統快速查看。需要原生標記／分享工具時可用 ⌘⇧5；停用本 App 截圖功能後 ⌘⇧3／4 也恢復系統行為，該路徑才遵循系統截圖儲存位置。

## 雙機與遠端

Mac mini固定外接鍵盤、MacBook內建鍵盤，只有MacBook開啓Fn交換。兩端都裝同版、先用一般模式；[雙機步驟](Resources/TwoMacAcceptance.md)涵蓋UC兩個方向及來源Terminal／目的TextEdit。CRD incoming host用Google簽章身份辨識，raw Ctrl在Mac目的端翻譯，已是Command通過；遠端Windows viewer保持Windows Ctrl。UC隱藏metadata與不同Remote組合仍需實機驗收，不承諾100%。

## 資源與驗證

一般模式沒有250ms／1s固定閒置輪詢，只有按鍵、系統通知及明確deadline；一般打字不會為計數喚醒主執行緒，遠端來源結束由kqueue事件通知。HID使用XPC ownership lease和Driver回報，放開所有鍵後不輪詢；尚有held output時保留單次安全檢查。截圖單輪、臨時PNG直接clipboard，TIFF／PDF按預算處理。代碼審查或CI不證明CPU穩定0.0–0.1%、完整App記憶體峰值、硬件交接或Driver恢復已通過。

OCR 目前停用：設定頁與選單沒有文字擷取入口，App 不封裝 OCR worker，不啟動辨識或載入 Vision／CoreML。原始碼與測試保留，內部開關位於 `ProductFeatures.screenshotTextRecognition`，預設為 `false`。一般截圖複製的是圖片，不需要 OCR。

[2026-10-19 資源研究](Docs/BackgroundResources-2026-10-19.md) 分開記錄已安裝 build 54 的背景量測與 build 55 的合成 UI 生命週期檢查，附可重現數據。液態玻璃可見時的 GPU 成本仍待實機 profiling；無 GUI 自檢不能當成完整 App 的記憶體數字。

- [操作說明](Resources/UserGuide.md)
- [人工驗收八類功能](Resources/AcceptanceGuide.md)
- [外部審查逐項核對、修復與支援缺口](Docs/DualModeReview-2026-10-03.md)

## 建置

```sh
bash scripts/build-app.sh
bash scripts/package-single-app.sh
bash scripts/package-app-dmg.sh
```

產出arm64 Release App與可拖入Applications的DMG，進階payload封裝於App內。Pinned SDK準備不需要安裝系統Driver；GitHub無.git ZIP仍可建置，來源會明確標記為archive，不冒用其他目錄的Git revision。`bash scripts/test.sh`是開發／Hosted CI測試入口，不執行權限授予或實際硬件驗收。

完整測試會先執行一般測試，再以獨立程序執行截圖與診斷快照記憶體回歸，兩者都必須通過；`bash scripts/test.sh -c release` 同樣涵蓋兩階段。128 MiB 增量門檻與 60 次處理次數不變。明確指定 `--filter`／`--skip`、`--no-parallel`、測試清單或自訂報告輸出時，腳本保留該次呼叫；量測整個程序記憶體時請只選該測試或使用 `--no-parallel`。

`BridgePerformanceCheck` 是不封裝進 App 的離線工具，提供 `--modifier-cycles`、`--routing-updates`、`--preview` 與 `--ocr-roundtrip <App executable>`，只使用合成按鍵／產生的圖片。App 的 `--render-feature-checks <new output directory>` 用合成狀態離線輸出新頁面供版面檢查，不建立輸入控制器或顯示視窗。

第三方MIT資源及官方Driver許可證保留在Resources/Licenses。未經Apple Developer／DriverKit資格，不能把官方簽章dext冒充為自制WindowsMacBridge Driver。
