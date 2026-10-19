# Build 55：原生 macOS 設定介面與液態玻璃

背景 CPU／記憶體量測、設定與縮圖關閉後的物件釋放，以及尚待量化的 GPU 成本，另見 [資源研究](BackgroundResources-2026-10-19.md)。無 GUI 的自檢數字不是完整 App 的用量。

設定視窗改用 `NSHostingController`、`NavigationSplitView` 和原生 sidebar List，保留標準交通燈、可調分隔線與統一工具列。工具列提供側邊欄收合（⌃⌘S）和使用說明；診斷仍只在進階模式顯示。所有設定綁定與校準頁離開時的取消行為保留。

內容使用系統分組表單、語意色與 SF Symbols，移除上方擁擠的分頁列。macOS 26 以上的標準導覽、選單與玻璃按鈕採系統 Liquid Glass；較舊系統保留標準 macOS 控制項。視窗背景與控制交由系統繪製。窄視窗的自選快捷鍵可分行，表格長結果提供完整提示。

自製截圖預覽沿用 build 54 的即時複製流程，只共用 AppKit 材質元件。該元件以 `NSGlassEffectView` 呈現玻璃，macOS 14／15 使用 `NSVisualEffectView`；減少透明度或提高對比時改用實色底，並在顯示期間回應輔助使用通知。沒有新增輪詢、螢幕擷取、一般剪貼簿讀取或輸入服務。

API 與設計依據：[Apple Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)。

## 本機驗證

- 原始碼基底：main `ce33ccb241ce37f11f67f1eb790416ba53e9cab6`；分支 `codex/liquid-glass-ui-20261019`。
- macOS 27 / Swift 6.4 / macOS 27 SDK 的 arm64 Release App 建置、自我檢查與 OCR helper 自檢通過。HID codec、資源自檢及 deep strict codesign 通過。
- 完整 Debug 共 484 項測試通過，包含獨立程序的截圖記憶體回歸。新版 Swift Testing 分目標輸出 42、2、14、40、217、168、1 項，合計 484。
- `--render-feature-checks` 產生 16 張自有版面：完整設定視窗亮／暗色、最小 730×600、高對比、遠端校準、文字擷取與截圖縮圖。完整設定視窗使用與正式 App 相同的 window factory，並核對工具列存在及導覽圖示可載入。
- 日誌與產生圖在忽略的 `build/liquid-glass-20261019/`，不含使用者畫面或一般剪貼簿內容。

離線繪製不能驗收 WindowServer 的實際玻璃折射、實際鍵盤／VoiceOver 導覽、系統輔助使用開關切換或 macOS 14／15 實機外觀。人工步驟見 [AcceptanceGuide](../Resources/AcceptanceGuide.md)。本次原始碼及候選封裝與現有 main、GitHub Release、已安裝 App 分別追蹤。
