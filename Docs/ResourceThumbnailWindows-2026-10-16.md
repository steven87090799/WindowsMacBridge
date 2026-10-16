# WindowsMacBridge build 51：Windows 操作、截圖縮圖與 OCR 資源複查

本報告接續 [build 50 功能審查](/Users/steven/Documents/ChatGPT/我/Docs/FeatureReview-2026-10-16.md)、[完整逐檔審查](/Users/steven/Documents/ChatGPT/我/Docs/CurrentMainAudit-2026-10-15.md) 與 [修復報告](/Users/steven/Documents/ChatGPT/我/Docs/RepairReport-2026-10-15.md)。舊報告的版本、雜湊與測試結果保持為當時快照，本報告記錄後續需求變更。

## 基準與需求

2026-10-16 再次 `git fetch --all --prune`，本機 HEAD 與 `origin/main` 都是 `949fc1f4d005b84f969d98e12e4a37249bd147f8`；`origin/fix/final-production-hardening-20261003` 仍是祖先。工作分支 `codex/complete-audit-repairs-20261015`，尚未提交或推送。既有 HID 一秒期限修正已包含在基準，沒有把它重新列為缺陷。

使用者改為要求 Terminal／IDE 也採完整 Windows 相容操作，並希望 Windows 與 macOS 截圖鍵都有右下角縮圖、OCR 不常駐占用模型記憶體。本輪重新檢查修改檔與整合路徑，沿用未變更檔的先前逐檔審查，不宣稱本輪又逐行閱讀了整個專案。

最後來源清單共 280 檔：217 檔與已審查 main 雜湊相同、39 個原有追蹤檔修改、24 檔新增正式碼／測試／工具；生成報告、產物與 SDK 建置資料不計入。

## 確認與修正

| 項目 | 原因與修正 | 對應來源 |
| --- | --- | --- |
| Terminal／IDE 只翻譯剪貼簿 | 舊設計提前回傳剪貼簿規則；現在接著匹配一般、分頁、文字導覽與系統規則，兩套後端一致 | `KeyboardEventProcessor.swift`、`HIDTranslationEngine.swift` |
| Alt+F4 的執行限制 | 單改規則仍會被關窗執行器的 `.macOS` 限制擋下；改為所有允許本機翻譯的模式 | `ShortcutActionDispatcher.swift` |
| IDE 的 HID 系統傳輸分類 | 同步調整傳輸資格與 capture epoch 比較，避免 IDE 跟其他本機模式不一致 | `HIDTranslationEngine.swift`、`HIDProtocol.swift` |
| 說明與預覽 | 設定、使用指南與驗收指南移除「其他 Unix／IDE Ctrl 操作保留」；預覽使用同一套實際處理器 | `SettingsView.swift`、`ShortcutPreviewTests.swift`、相關文件 |
| Windows 截圖沒有浮動縮圖 | 成功寫入剪貼簿後才交給惰性建立的縮圖視窗，約五秒自動關閉；點擊開啟系統 Quick Look | `ScreenshotManager.swift`、`ScreenshotPreview.swift`、`ScreenshotThumbnailPresenter.swift` |
| OCR 與主程式的框架隔離 | Vision 移至獨立 `WindowsMacBridgeTextWorker`，主程式只保留有界 IPC；封裝時先簽 helper 再簽 App | `Tools/OCRWorker/`、`ScreenshotTextProtocol.swift`、`ScreenshotTextWorkerClient.swift`、`build-app.sh` |

本機 App、Terminal、IDE 共用的操作包含 Ctrl+C／V／A／X、S、Z／Y、F、T／W、文字導覽、Alt+Tab、Alt+F4 與截圖。Terminal 目前維持 Ctrl+C 複製、Ctrl+Shift+C 中斷命令。App 是否提供對應命令仍由該 App 決定；傳送快捷鍵不能當作該 App 功能已驗收。IDE 依整個 bundle 套用規則，沒有以 AX 猜測內嵌 Terminal 焦點。

## 資源與所有權

一般圖片截圖不會啟動 OCR。沒有 OCR 啟動預熱、常駐 worker 或模型輪詢；每輪最多一個辨識程序，完成即退出，取消／逾時與主程序退出會結束自己的 worker。輸入仍受 64 MiB、解碼與像素預算限制，辨識縮圖最多長邊 2560／400 萬像素，回覆最多 64 KiB／1,000 行。私有影像先 unlink 再透過 fd 傳入；主程式不保留辨識文字或寫入文字日誌。

OCR 執行期間仍需 CPU 與記憶體。程序退出會回收該程序的配置；macOS 的共享框架、檔案與模型快取由系統管理，不能承諾全系統記憶體立刻歸零。先前首次約 24 秒的延遲是在 Vision `perform`，模型初始化／編譯／快取或系統等待是可能原因，尚無證據能只歸因於模型載入；詳見 [延遲量測](/Users/steven/Documents/ChatGPT/我/Docs/OCRLatencyAndNoFeeAI-2026-10-16.md)。

其他使用例子：[macOCR](https://github.com/schappim/macOCR) 明確使用 Apple Vision；Apple 的[照片](https://support.apple.com/en-ie/guide/photos/pht6bc6bd5f5/mac)、[預覽程式](https://support.apple.com/en-euro/guide/preview/prvw625a5b2c/mac)與 [Safari](https://support.apple.com/en-ca/guide/safari/ibrw20183ad7/mac) 都提供 Live Text。Apple 未公開保證這些 App 與本程式使用相同的辨識 request 或模型快取，不能據此推論本程式 OCR 沒有任何額外開銷。

縮圖長邊最多 480 像素、PNG 最多 1 MiB；這是圖片資料上限，不是整個視窗／App 的記憶體上限。未截圖時不建立縮圖視窗；沒有固定輪詢。UI 不持有全尺寸 bitmap。一般截圖原圖留在磁碟供使用者點擊查看，五秒消失或查看結束後清理；已明確儲存的桌面圖片不會刪除。Quick Look 只在點擊後啟動，同時最多一個自己的查看程序。

Win+Shift+S、PrintScreen、Alt+PrintScreen、Win+PrintScreen 與攔截的 ⌘⇧3／4 共用完成流程。取消、失敗、過期或 OCR 工作不顯示圖片縮圖。由 macOS 自己產生且已有系統縮圖的舊式接收路徑不額外顯示第二個。此縮圖提供系統快速查看；它不是 Apple 截圖標示編輯器。

## 驗證與界線

本輪結果與檔案雜湊記錄於 [驗證清單](/Users/steven/Documents/ChatGPT/我/build/resource-thumbnail-20261016/verification.json)。包括 Debug／Release 完整回歸、獨立程序的重複截圖記憶體測試、原生 Vision 合成圖片辨識、取消／逾時與主程序退出、縮圖資料／檔案所有權、完整本機快捷鍵與 HID 系統動作、封裝簽章與框架依賴，以及六張離屏合成介面。

Debug 與 Release 各 **473 項通過**（42＋2＋14＋40＋206＋168＋1），最後一項為獨立程序的截圖記憶體回歸。App、OCR helper 與 HID 無輸入自檢、`codesign --verify --deep --strict`、shell 語法與 `git diff --check` 通過。主執行檔沒有直接連結 Vision，helper 連結 Vision 且沒有直接連結 AppKit／SwiftUI；三次 metadata-only 啟動的 dyld 清單都沒有 Vision／VisionKit／CoreML。安裝器 62 項與監測工具 6 項沿用前輪結果；本輪比對相關輸入檔雜湊，沒有宣稱重新執行。

| 新產物量測 | 結果 | 範圍 |
| --- | --- | --- |
| 三次 OCR | 23.124、0.239、0.232 秒 | 自產英文圖片；仍存在首次延遲，沒有預熱 |
| worker 最大 RSS | 222.84 MiB | 三個獨立 worker 的程序高水位；不代表整個系統峰值 |
| 診斷父程序 footprint | 約 5.24 → 5.63 MiB | IPC 診斷程序，不是完整 GUI |
| 主程序退出 | 啟動前／辨識中兩種情境都退出，沒有輸出舊結果 | 僅結束本測試建立的 worker |
| build 50／51 metadata 自檢最大 RSS | 約 12.31 → 11.20 MiB（各三次的中位數） | 不是閒置 GUI 的長時間效能比較 |

兩次不同版本的自檢不能證明整體 App 的固定節省量；本輪能確認的是依賴隔離、按需生命週期與有限測試下的有界資源。新產物為 **0.6.0 build 51**，已安裝的版本仍為 **build 47**。

未安裝或啟動候選版的鍵盤 GUI，未變更 TCC、Driver 或實體鍵盤設定，沒有讀取使用者畫面與一般剪貼簿。實體鍵盤、Terminal／IDE 具體命令、浮動縮圖焦點／位置／點擊查看、跨 Mac／遠端與完整 GUI 長時間 CPU／footprint 仍需依 [驗收指南](/Users/steven/Documents/ChatGPT/我/Resources/AcceptanceGuide.md) 實測。有限測試無法證明零缺陷或全系統效能絕對最佳。
