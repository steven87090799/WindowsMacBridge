# Build 62 修正與資源檢查（2026/10/23）

檢查基準為 `codex/fix-macbook-fn-control` 的 `66fed940e2b75dfbe6bd7a24c7ed5453aaef7c3f`（`v0.6.0-preview.9`）。本文件描述該提交之後的本機工作目錄修正；既有 tag 與 GitHub Release 未變更。

## 已修正的問題

| 問題 | 修正及證據 |
|---|---|
| 只有 aggregate flags 的輸入，左右 Ctrl 交錯放開、Shift 仍按住時，另一側 Ctrl 可能殘留並使狀態失去同步 | 明確收到整組已放開時清除該組兩側；不恢復先前已失效的信任狀態。左右放開順序及失效狀態均有回歸測試。 |
| 通用控制／獨立來源的第一個右 Option 事件先補了左側狀態，使右 Option+P 或右側 App Switch 判斷錯誤 | 先處理真實側邊事件，再補足獨立來源的 aggregate flags；覆蓋八個修飾鍵側別、自身輸出忽略與右 Option 快捷鍵。 |
| 遠端獨立旗標路徑仍把重複 down 當成 toggle，App Switch 清理時可能送出錯誤 Command 側別 | 獨立來源使用狀態解碼，原生有 side bits 時將解碼結果傳入 router；無獨立旗標的來源維持來源隔離。重複右 Alt 的舊版測試實際得到 55，修正後正確得到 54。 |
| 一個鍵盤服務成功、另一個服務失敗時，摘要隱藏錯誤 | 摘要同時呈現成功數及失敗原因，測試原版失敗、修正版通過。 |
| 原生鍵盤通知後端缺少最終釋放時的解除註冊，refcon 直接指向後端物件 | 用弱 owner 的 context 與明確的 IOKit 資源清理；物件最終釋放會解除通知，背景釋放時將資源移交主執行緒完成清理。連續 20 次建立／釋放測試確認後端與 context 都釋放。 |
| 診斷停用仍預配置 128 個紀錄欄位；每次發布先 compactMap 再排序；到期後設定變更可能重新啟動窗口 | 新的 InputDiagnostics 於第一筆紀錄才配置，依 ring 順序輸出最新資料，到期／關閉清空儲存，只允許明確 off→on 重新開始。共用既有單次到期計時器，閒置時也會清理；停用時不新增每事件時鐘查詢。 |
| 每個修飾鍵事件及獨立來源同步都掃描 128 個空按鍵欄位 | 由既有 pressCount 判斷，無待處理按鍵時跳過掃描；保留已按住按鍵的 repeat／up 配對與中斷保護。 |

最初四項功能回歸案例在修正前共產生 10 個 assertion issues，修正後全數通過。

## 測試與建置

- 最終 `bash scripts/test.sh`：535 項測試通過，0 失敗。包括按鍵配對、缺失事件保護、遠端隔離、HID、截圖、設定／觀察者生命週期，以及獨立程序的兩項記憶體回歸。
- `bash scripts/build-app.sh`：成功；主程式與 Finder extension 均為 arm64、SDK 27.0、最低 macOS 14.0，ad-hoc 簽章驗證通過。
- App 自我檢查與資源檢查通過，GUI 未載入 OCR frameworks。
- `git diff --check` 通過。
- 本機 App：`/Users/steven/Library/Caches/WindowsMacBridge/e046ae762ceb/Artifacts/WindowsMacBridge.app`。標示 0.6.0 build 62、基準 revision 66fed94、source state **modified**，是本次工作目錄的驗證產物，並非原本 tag 的未修改發佈包。

## 效能與記憶體

`BridgePerformanceCheck --modifier-cycles` 是離線合成測量：每循環包含兩次 Ctrl down、C down/up 與 Ctrl up，不建立 Event Tap、不送按鍵、不改鍵盤映射、不讀取使用者剪貼簿。每模式量測三輪，每輪 200,000 循環／1,000,000 事件。比較基準已包含功能修正，差異是空欄位掃描最佳化，使用相同 release 編譯條件。

| 核心路徑 | 最佳化前 P50（每循環） | 最佳化後 P50（每循環） | 耗時減少 |
|---|---:|---:|---:|
| 本機狀態處理 | 0.9917 µs | 0.0750 µs | 92.4% |
| 獨立來源狀態處理 | 2.6458 µs | 0.4459 µs | 83.1% |

上述數值是三輪中位數，不代表整個 App、真實輸入延遲或整台 Mac 的加速比例。

- 診斷紀錄與快照連續更新 50,000 次：最終測試 `phys_footprint` 為 4,555,280 → 4,555,280 bytes，增加 **0 bytes**。最多保留 128 筆；到期後紀錄及 ring slots 都為 0。rule／application／detail 分別限制為 256／256／1024 UTF-8 bytes。
- 合成修飾鍵循環：第一輪量測有 245,760 bytes 的暖機／量測陣列頁面增量，其後五輪皆為 0 bytes 增量。
- `leaks -quiet --atExit -- BridgePerformanceCheck --modifier-cycles`：工具回報 **0 leaks／0 leaked bytes**。
- 0／1／16 個來源的 routing update 壓力測量均維持固定來源上限，記憶體增量為 0～16 KiB（另有首輪量測暖機 240 KiB）。
- 核對主要背景路徑：遠端 registry／待辦與動作佇列有上限；主執行緒通知會合併；效能頁隱藏時停止取樣；截圖限制檔案／像素大小並有取消與釋放路徑。既有相關回歸測試均通過。

原始效能數值與測試摘要存於 [Build62-Review-Metrics-2026-10-23.json](Build62-Review-Metrics-2026-10-23.json)。

## 實際安裝與系統框架界線

檢查時 `/Applications/WindowsMacBridge.app` 及正在執行的程序仍為 build 60（fca8408）。其實體 footprint 約 68.0 MiB；此數字是舊 App 的當下讀值，不能當作本次產物的執行驗收。

舊程序的 `leaks` 回報 417 個配置、20,016 bytes，根節點是三組 `LNDaemonApplicationInterface`／`LNProcessInstanceRegistryClient.makeXPCConnection` 的 AppIntents／Foundation 循環。另以完全不含 WindowsMacBridge 程式碼的 AppKit／SwiftUI 隱藏視窗重現相同三組循環（414 個配置、26,320 bytes）。因此這項現象可獨立於本專案輸入處理重現；沒有證據顯示由本次 Fn／Ctrl 修正新增。工具對 hardened process 亦提示內容讀取限制，不能以這些量測宣稱所有系統框架永久零洩漏。

最小重現流程：建立 `NSApplication.shared`，設定 activation policy 為 prohibited，建立未顯示的 NSWindow 與只含 Text 的 NSHostingView，清除 contentView 並關閉視窗，執行 0.5 秒 run loop 後退出，再以 `leaks --atExit` 檢查。未啟用鍵盤擷取、映射或本專案服務。

本次完成原始碼修正、全套自動測試及本機建置，未替換正在執行的 App。修正後的實體 Fn／Ctrl、雙 Mac 通用控制與各第三方遠端軟體仍需在安裝後以受控實際操作驗收；自動測試不能代替這些路徑。缺乏 side bits 的傳輸也無法精確識別「另一側仍按住時」每一側的放開，整組中立時的清理與保守判斷仍有必要。
