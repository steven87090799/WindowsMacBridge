# 設定外觀、狀態燈與按需效能頁

## 行為

- 新增一般模式也能開啟的「CPU 與記憶體」頁，顯示整台 Mac 的 CPU、記憶體，以及 WindowsMacBridge 主程式的 CPU 與 physical footprint。
- 只在專頁掛載、視窗可見且未最小化、未被完全遮住、App 未隱藏且工作階段醒著時取樣。每 2 秒一次，容許 0.4 秒 timer tolerance。停止時取消 timer 並清空前次讀數；重新開始不計入離頁期間。沒有歷史陣列、檔案寫入或背景監測服務。
- 此頁的 view 持有 monitor；主程式的 BridgeController 不持有它。離頁、視窗關閉與 owner 釋放皆有停止路徑。視窗通知驅動可見性判斷，不用另一個 timer 輪詢視窗。
- 移除輸入法頁與診斷摘要原本附帶的記憶體讀取。輸入法切換次數仍屬功能統計；它與效能讀數分開。
- 整機 CPU 以所有核心合計為 100%；App CPU 以一個核心為 100%。首次讀數須等第二次取樣才有 CPU 百分比。核心讀取失敗不顯示假的零。
- 系統記憶體使用量為 active + wired + compressor physical pages，並顯示 physical total、compressor physical bytes。這是明確標示的核心分類，不宣稱等同活動監視器所有分類或記憶體壓力。
- App memory 只代表主程式，不包含 Finder Sync 或 OCR 輔助程式。每次核心取樣取得的 host send right 都有釋放。

## 外觀

- 內嵌 NSWindow 沒有穩定產生自動側邊欄按鈕，因此保留標準 SwiftUI 工具列按鈕，隱藏它的多餘圓形共用背景；初始鍵盤焦點移到導覽清單。保留鍵盤快捷鍵、系統焦點和輔助使用能力。
- 導覽面板背景明確使用 macOS 26 的 NSGlassEffectView，文字與綠燈放在材質上方，設定內容保留可讀的標準背景。較舊系統使用 NSVisualEffectView；減少透明度或提高對比時改用實色。沒有自訂持續動畫或 render timer。
- 唯音／ABC 成功指示燈由實際來源與守護狀態決定；等待、來源不符、暫停或守護關閉不會顯示成功綠燈。文字保持可讀，並非只靠顏色傳達狀態。
- 截圖圖面維持 296 × 172 pt；底下兩行改成一行。標題 13 → 11 pt、提示 11 → 10 pt，卡片高度 248 → 220 pt，仍可按圖片快速查看或關閉。

## 驗證

- `PerformanceMonitorTests`：可見時才開始、停止與重開、舊 callback 失效、owner 釋放取消 timer、讀取失敗、CPU tick wrap、App 多核心百分比、記憶體分類、所有隱藏狀態與核心 metadata adapter。
- `GuardControllerIntentTests`：成功來源才符合綠燈條件，來源不符、未知、停用與 host suspension 都不符合。
- `--ui-resource-check <新檔案>`：產生的離屏視窗測試可見／遮住／最小化／恢復／休眠／醒來／卸載專頁通知；另外反覆建立及釋放 10 次真正的 PerformanceView，追蹤弱參照。只讀本程序與核心 metadata，不啟動鍵盤引擎。
- `--render-feature-checks <新目錄>`：20 張自產內容的淺／深色、最小尺寸、高對比版面，包含綠色唯音狀態、效能頁與縮圖。離屏圖片無法證明真實桌面背景折射、實體快捷鍵或所有輔助使用設定的驗收。
- CI 另外執行完整 Debug／Release、獨立程序記憶體回歸、Installer、Monitoring、簽章與無 `.git` 原始碼打包。

Apple 依據：[Liquid Glass 的形狀、標準控制項與成本建議](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[系統介面更新](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)。此版沒有用 GPU 百分比或「零資源」宣稱取代實測。
