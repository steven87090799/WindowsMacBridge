# WindowsMacBridge v0.6.0（build 63）

這是本次選定的正式發佈版本，適用 Apple Silicon（M 系列）Mac、macOS 14 以上。提供包含完整 App 的 ZIP 與可拖放安裝的 DMG，兩者均由 GitHub Actions 從發佈提交建置。

## 更新內容

- 修正通用控制重複 Ctrl 事件造成複製／貼上失敗，以及雙側修飾鍵交錯放開後的殘留狀態。
- 修正右側修飾鍵與遠端獨立輸入的辨識及 App Switch 放鍵配對。
- Fn／Ctrl 狀態清楚區分「映射已寫入」與實體操作確認，部分鍵盤服務失敗時保留錯誤提示。
- 診斷紀錄按需配置、到期釋放，限制最多 128 筆及每筆文字長度；移除空按鍵欄位的重複掃描，補齊原生鍵盤通知清理。
- 整合前次 Windows 剪貼簿規則、截圖預覽置中／啟用與清晰的 Liquid Glass 側邊欄。
- OCR 維持停用，GUI 不封裝 OCR worker、不載入 OCR frameworks。

本機 535 項 Swift 測試通過。診斷連續更新 50,000 次的測量未觀察到記憶體增長；離線核心循環的中位耗時降低約 83–92%，此比例不代表整個 App 或實際輸入延遲。完整量測及限制見 [審查紀錄](Build62-Review-2026-10-23.md)。GitHub Actions 另執行 Debug／Release、安裝復原、資源監測與完整封裝檢查；精確結果以本次提交的 Actions 狀態為準。

## 下載與在另一台 Mac 安裝

建議下載 **WindowsMacBridge-0.6.0-macos-arm64.dmg**。也可下載 **WindowsMacBridge-0.6.0-app-macos-arm64.zip**，解壓後取得同一個完整 App。`WindowsMacBridge-build-info.json` 記錄建置提交、build、簽章方式與 SHA256；下載旁邊的 `.sha256` 檔可核對封裝內容。

1. 從選單列正常結束舊版，等待鍵盤交換還原，再將完整 `WindowsMacBridge.app` 放到「應用程式」並取代舊版。既有偏好設定保留。
2. 從「應用程式」開啟，確認版本 **0.6.0（63）**。新電腦先使用預設一般模式。
3. 在該台 Mac 分別核准輔助功能與輸入監控，回 App 確認；需要截圖再核准螢幕錄製。重新簽章後 macOS 可能要求再次核准或重新開啟。
4. MacBook 如需交換 Fn／左 Ctrl，在一般設定明確開啟。另一台電腦的權限、Karabiner 個人設定及鍵盤還原 journal 不會包含在 App 中，請勿複製舊機的還原紀錄。
5. 通用控制由 macOS 設定連線，兩台 Mac 均使用此版本並各自完成權限設定。用文字編輯測 C／X／V／A，兩個方向分別測 Ctrl+C／V；MacBook 另測原左 Ctrl→Fn 及關閉交換後的還原。

一般模式不需要另裝 Driver、Root helper、Xcode 或 Homebrew。App 內含選用的進階 HID 安裝材料；只有明確選擇進階模式並安裝時才會使用。

## 簽章與支援界線

本版使用 **ad-hoc 簽章，尚未 Apple 公證**；「正式版本」表示本次選定的發佈版本，並不代表取得 Apple 認證。若 macOS 阻擋首次開啟，確認來源後使用「隱私權與安全性」中的系統開啟選項。

build 62 的前次受控操作已確認該 MacBook 內建 Fn／Ctrl 與一條通用控制輸入路徑。build 63 的新增修正有自動回歸測試，另一台 Mac 的實際鍵盤、權限、雙向通用控制與選用 HID／Driver 仍須依上述步驟確認。安裝與建置成功不等於所有硬體及遠端軟體均已驗收。
