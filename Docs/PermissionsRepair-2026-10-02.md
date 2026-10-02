# 授權清單與鍵盤事件修復（0.5.17 / build 33）

使用者的 build 32 GUI 已確認 AX／按鍵輸出和螢幕錄製取得、主 App Input Monitoring 未取得。系統 `CGGetEventTapList` 顯示兩個已啟用的 annotated taps 實際 mask 都只有 4096（flagsChanged）；沒有 keyDown／keyUp，不能把 Active 視為鍵盤／截圖就緒。

授權頁固定平鋪八項，每項標示用途、必要／選用、系統位置及自己的操作。AX 與按鍵輸出共用同一設定開關，兩個 native checks 都通過才綠色。主 App 與 helper 各有自己的輸入監控列。開啟設定、申請成功回傳、安裝完成均不能當成授權通過。

第八項是 macOS 截圖資料夾存取。提供 NSOpenPanel 選取目前實際的截圖資料夾，不更改系統儲存位置。沒有公開 TCC 資料夾 preflight API，因此啟動時保持未檢查；使用者選取或按重新檢查後，在 utility worker 做一次有上限的原生目錄讀取，成功才綠色。不列舉整份目錄、不開啟既有圖片、不要求完整磁碟存取、不輪詢。更改截圖儲存位置後清除先前確認狀態。

Driver 核准直接讀系統延伸功能清單，要求官方 Team／bundle ID、enabled、active 和 activated enabled 全部符合；讀取失敗保持未檢查。此查詢僅於啟動、返回授權頁及使用者重新檢查時執行，非鍵盤 callback，也不持續輪詢。helper 只採目前連線最新一秒內的經驗證回報，未使用 HID 時不啟動它來檢查。

主 App 缺輸入監控時停止鍵盤 tap 及 250ms EventTap safety timer。授權改變會重新建立 tap；建立／重新檢查時核對實際事件 mask，拒絕僅有修飾鍵的 tap。Windows 截圖提示缺少輸入監控；macOS 截圖檔案觀察維持獨立。HID 截圖文字不再把選中後端當成 Driver／helper 已就緒。

更新仍使用臨時簽章，可能需對 build 33 重新核准權限。此次不自動核准 TCC、不重設其他 App 權限、不修改共用 Driver。編譯及權限／事件遮罩回歸檢查不代表 UC、HID 實體輸入或 Driver 已驗收。

驗證：只執行 PermissionChecklistTests、DriverApprovalTests、KeyboardEventTapCoverageTests、KeyboardPermissionRequestTests 與 ScreenshotFolderAccessTests，13 個檢查通過。沒有執行全套、跨機、鍵盤持鍵或記憶體壓測；TCC 資料夾與 HID／Driver 核准仍由使用者實際操作驗收。

Release 建置、App 與內含 payload 簽章檢查及單一 App 封裝完成。產物是 `build/download/WindowsMacBridge-0.5.17-preview.5-app-macos-arm64.zip`，ZIP 頂層只有 WindowsMacBridge.app。

此機更新結果：內含 launcher 回傳 0，App 與 helper 均安裝為 build 33，沒有 `.install-recovery`，GUI 從 `/Applications/WindowsMacBridge.app` 啟動並顯示八項未折疊清單。GUI 的鍵盤控制、主 App 輸入監控、螢幕錄製都顯示未取得；登入啟動與 Finder 擴充經原生 API 確認才綠色；EventTap 模式的 helper 與尚未驗證的截圖資料夾保持未檢查，Driver 顯示未核准／未啟用。没有代替使用者核准任何 TCC 或 Driver 權限。
