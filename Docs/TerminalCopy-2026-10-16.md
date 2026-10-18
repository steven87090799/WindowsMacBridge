# WindowsMacBridge build 52：Terminal Ctrl+C 依選取狀態執行

依使用者後續明確選擇，Terminal 的 Ctrl+C 改採 Windows Terminal 的條件式語意，取代 build 51 的固定複製。此前的 [build 51 報告](/Users/steven/Documents/ChatGPT/我/Docs/ResourceThumbnailWindows-2026-10-16.md) 保留為歷史快照。

| 狀態 | Ctrl+C 的行為 |
| --- | --- |
| 確認有選取文字 | 送出 Command+C，交給前景 Terminal 複製 |
| 確認沒有選取文字 | 送出 Control+C，交給 Terminal 中斷命令 |
| 選取資訊不可用、超時或格式不明 | 僅嘗試複製，避免誤中斷；Ctrl+Shift+C 仍可明確中斷 |

這是 Terminal 模式的行為；IDE 整個 App 仍套用其 Windows 快捷鍵規則，沒有新增猜測內嵌 Terminal 焦點的機制。Remote Windows／VM／Game／停用與安全輸入等既有分流保留。

## 實作與資源

`WindowsCompatibilityRules.terminalClipboard` 將 Ctrl+C 變成條件式 action，EventTap 與 HID 共用。原始 key-down／repeat／key-up 會成對處理，辨識後才送出完整的複製或中斷按鍵對；按住不會重複排入 action。一般模式的 bounded mailbox 滿載時不會把這個未確認動作退回原始 Ctrl+C，以免誤中斷命令。

`TerminalSelectionReader` 只在明確 Ctrl+C 後於背景工作讀取前景 Terminal 的焦點與選取範圍 metadata，不讀取選取文字、整份文件、畫面或剪貼簿，不新增背景輪詢、常駐程序或選取快取。AX timeout 僅設在本輪使用的個別 element，每次 25 ms；最多處理 16 個範圍，不遍歷 AX 樹。支援單一與非連續範圍，拒絕負數、溢位、未知型別與不合上限的結果。查詢前後確認焦點，查詢完成後再次確認來源、權限、App／session／policy epoch 與原有 0.6 秒 action 期限。

選取範圍依 [Apple AXSelectedTextRange](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute) 與 [AXSelectedTextRanges](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangesattribute) 介面讀取；不同 Terminal 是否提供正確 AX 資訊仍須實機驗收。無法確認時不推定沒有選取。

HID 新增固定 action ID `terminal.copyOrInterrupt`，App／helper 的 XPC 協定升至 **8**，拒絕舊版配置，避免混用背景元件版本。這與 Driver 的 client protocol 是不同層級；`--hid-self-check` 顯示的 `protocol=7` 屬於未變更的 Driver codec。進階模式須搭配相符版本的背景元件；本輪沒有安裝或改動目前服務。原有 HID 一秒期限修正與 ownership lease 沒有回退。

規則預覽顯示「有選取：複製；無選取：中斷命令」，另說明未知狀態的處理。預覽本身不執行 AX 查詢。設定、README 與操作／驗收指南都同步更新。

## 驗證

完整來源雜湊、測試與候選 App 記錄於 [驗證清單](/Users/steven/Documents/ChatGPT/我/build/terminal-copy-20261016/verification.json)。新增測試使用合成範圍與注入的查詢／按鍵發送器，不讀取使用者 Terminal、不送出真實按鍵。

驗證涵蓋有選取／沒有選取／未知、單一／多範圍、錯誤型別與非法數值、非 Terminal 不查詢、查詢期間暫停／本機規則失效／權限撤銷／切 App／deadline／來源撤銷，以及兩套後端的持鍵／放鍵配對、HID 固定 action 編解碼與舊協定拒絕。完整 Debug／Release 回歸、候選 App 自檢、HID 無輸入自檢、OCR helper 自檢、深層嚴格簽章與離屏介面也納入本輪驗證。

Debug／Release 各 **478 項通過**（42＋2＋14＋40＋211＋168＋1），最後一項記憶體回歸在獨立程序執行。新增的五個測試函式包含三種選取結果與六種撤銷情境的參數化案例；沒有把參數案例重複累加成測試函式數量。安裝器與監測工具沿用前輪 62／6 項結果，相關來源雜湊另行核對，沒有宣稱本輪重跑。

本輪沒有重新量測 OCR 冷啟動與 IPC 峰值；OCR worker、IPC 與影像預算來源未變，沿用 build 51 的相關證據，並比對來源雜湊。一般 Vision 合成圖片測試仍由完整回歸執行。不把 build 51 的 23 秒／223 MiB 量測標成 build 52 的新測量。

本機與 `origin/main` 更新後仍為 `949fc1f4d005b84f969d98e12e4a37249bd147f8`，修復工作位於未提交的 `codex/complete-audit-repairs-20261015`。候選版為 0.6.0 build 52，已安裝版本仍為 build 47；未啟動候選版輸入引擎，未改 TCC／Driver／實體鍵盤，尚未用真實 Terminal 命令驗收。有限測試不代表所有 Terminal 都已驗收。
