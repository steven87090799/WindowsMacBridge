# Build 52 本機安裝與原始碼交付

2026-10-16，依使用者要求安裝到本機並上傳 GitHub。前面的審查與功能報告保留各輪當時的版本／未安裝狀態；本文件記錄後續交付。

## 已完成的本機安裝

- 將 0.6.0 build 47 正常結束，保留原 App 與設定備份，再安裝並啟動 **0.6.0 build 52**。
- 安裝位置為 `/Applications/WindowsMacBridge.app`；未修改 Root 服務、Driver、進階模式開關或其他 App 權限。
- 原有設定仍為總開關啟用、進階模式關閉、Fn／Ctrl 交換關閉、截圖自動複製開啟。雖然儲存的 backend 選項是 deviceHID，進階模式關閉時實際使用 EventTap。
- 使用完整 App 封裝，包含 OCR helper 與選用的進階安裝資源；沒有執行進階安裝器。
- 封裝前後主程式的 `__TEXT` 各節雜湊一致，OCR helper 與 Info.plist 一致。完整封裝會更新外層簽章，因此其 Mach-O 全檔雜湊與未內嵌安裝資源的測試產物不同，不能把簽章差異誤當成執行碼改變。
- 以具 inode／device 所有權核對的 retirement 與 exclusive publish 替換；完整封裝的 985 個檔案／連結內容與安裝後一致，深層嚴格簽章、App／HID／OCR helper 自檢通過。

安裝後從實際 GUI 確認版本為 build 52。macOS 顯示輔助功能、輸入監控與螢幕錄製未取得，需重新核准；因此安裝與啟動成功不表示鍵盤、截圖、OCR、Driver 或實體裝置驗收通過。登入項目顯示已核准；本輪沒有變更該設定。

安裝來源是完整測試的未提交工作目錄。App 的版本資訊如實記錄基準 `949fc1f4d005b84f969d98e12e4a37249bd147f8` 與 modified 狀態，不會把其後產生的 Git commit 冒稱為已安裝產物的內嵌 revision。上傳前逐檔比對了測試來源清單，原始碼與測試內容沒有漂移。

## 原始碼與驗證

本次上傳包含 R01–R06 修復、獨立記憶體回歸、快捷鍵規則預覽、遠端校準、本機按需 OCR、截圖縮圖、完整 Terminal／IDE Windows 相容規則與 Terminal 選取式 Ctrl+C。

- [逐檔審查與基準](CurrentMainAudit-2026-10-15.md)
- [R01–R06 修復](RepairReport-2026-10-15.md)
- [三項功能與效能複查](FeatureReview-2026-10-16.md)
- [縮圖、Windows 規則與資源隔離](ResourceThumbnailWindows-2026-10-16.md)
- [Terminal 選取式 Ctrl+C](TerminalCopy-2026-10-16.md)

本機 Debug／Release 各 478 項通過，記憶體回歸另以獨立程序執行。安裝器 62 項與監測工具 6 項沿用前輪相同來源的結果，GitHub CI 另在提交後驗證。測試日誌、安裝交易／設定備份與本機狀態清單保留於忽略的本機建置目錄，不上傳私人設定、程序資料或備份。

[可隨原始碼查閱的驗證清單](Build52Validation-2026-10-16.json) 包含 282 個來源檔的雜湊、測試函式數、日誌雜湊與安裝摘要；移除本機程序、私人設定及備份路徑。這份清單記錄安裝首次啟動時的權限狀態，其後狀態須從實際 App 重新檢查。

上傳工作分支並建立 PR 供檢查；沒有因此自動合併 main 或發佈正式 Release。CI 的精確提交狀態以 PR checks 為準，不將本機測試結果標成遠端 CI 結果。
