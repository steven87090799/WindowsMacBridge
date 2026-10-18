# WindowsMacBridge：Apple AI API 與功能建議

查核日期：2026-10-16，Asia/Taipei。這份文件是官方 API 調查與產品提案；下列 AI 功能尚未加入 App。本輪已實作的規則預覽、遠端校準與 Vision OCR，見 [功能與效能複查報告](/Users/steven/Documents/ChatGPT/我/Docs/FeatureReview-2026-10-16.md)。

## 可以使用的官方 API

| API | 適合本專案的用途 | 版本與限制 |
|---|---|---|
| [Foundation Models／SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) | 摘要、文字整理、分類，以及產生符合指定結構的設定草稿 | 本機模型 API 自 macOS 26 起提供；需要支援 Apple Intelligence 的裝置、可用地區及就緒的模型。使用前查 `availability` 與 `supportsLocale`。 |
| [Translation](https://developer.apple.com/documentation/translation/translating-text-within-your-app) | OCR 後翻譯、原文與譯文並列 | 自訂翻譯 API 自 macOS 15 起提供；先查語言配對，尚未安裝的語言模型由系統徵詢下載。 |
| [Writing Tools](https://developer.apple.com/documentation/appkit/writing-tools) | 在 OCR 結果編輯器內提供系統改寫、校對與摘要 | 標準 AppKit 文字控制項可整合系統功能，仍受 Apple Intelligence 可用性限制；不是讀取任意 App 文字的通用授權。 |
| [SpeechAnalyzer／SpeechTranscriber](https://developer.apple.com/documentation/speech/speechanalyzer) | 按住按鍵口述文字、短語音命令 | macOS 26 起；須檢查裝置與語言支援、管理語音資產、取得麥克風授權。應在明確操作時才錄音。 |
| [App Intents](https://developer.apple.com/documentation/appintents) | 將「開啟規則預覽」「暫停轉換」「開始文字擷取」接到捷徑、Spotlight 與 Siri 支援的入口 | 各動作仍遵守既有權限與輸入政策；曝光動作不等於取得跨 App 的無限制控制權。 |

Apple 的[支援說明](https://support.apple.com/en-us/121115)列出 Apple silicon Mac 與繁體中文支援；特定功能仍可能有地區、語言和模型狀態差異。

macOS 27 的 [Foundation Models 更新](https://developer.apple.com/documentation/updates/foundationmodels)另外加入多模態圖片提示等能力。可以做「框選錯誤視窗後說明內容」；這是新提案，現有 OCR 只辨識文字。若需要更強推理，可研究 [Private Cloud Compute API](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)，但它需要開發者資格與 managed entitlement、網路連線，並有每日配額，不能承諾無限制或永遠免費使用。

## 建議開發順序

| 順序 | 功能與具體操作 | 實作邊界 |
|---|---|---|
| 1 | **截圖智慧文字面板**：框選後顯示原文，按一下翻譯成繁中、整理段落或產生三點摘要，再複製選定結果。 | OCR、翻譯、生成分開按需執行；保留原文，失敗不覆蓋剪貼簿。辨識、翻譯和摘要各自標示處理狀態。 |
| 2 | **中文設定助理**：輸入「Safari 用 Windows 快捷鍵，VS Code 保留原生操作」，產生 App 與既有模式的設定草稿，先進規則預覽再套用。 | 使用結構化輸出，只能選程式支援的模式／App；驗證 bundle ID、容量與衝突。模型不產生可執行程式碼，也不直接控制鍵盤。 |
| 3 | **智慧純文字複製**：去除 OCR 斷行、轉條列或 Markdown、整理錯誤訊息供貼上詢問。 | 原文與結果可比較；程式碼、網址、序號保留精確複製選項，避免模型改錯字元。 |
| 4 | **Siri／捷徑入口**：語音或捷徑打開預覽、暫停轉換、叫出文字擷取。 | 先做範圍明確的 App Intents，沿用現有狀態與權限檢查；切換前景或受保護場景仍會取消過期工作。 |
| 5 | **框選錯誤說明**：選一個錯誤畫面，說明可能原因，或將使用者選定的診斷資料整理成可分享報告。 | macOS 27 圖片能力或先 OCR 再處理文字；列出實際證據與推測，保留原錯誤文字，避免把模型建議當作確診。 |
| 6 | **按住說話**：短時間口述後取得文字，選擇是否整理再複製。 | 較高的資源、授權及收尾成本，排在文字功能後；不常駐錄音，取消即停止。 |

優先建議做 1、2：它們能直接接到本輪新增的 OCR 與規則預覽。4 的動作整合也很實用，而且不必讓每次操作都經過語言模型。這些優先順序是依本專案用途與目前架構提出的工程判斷，並非 Apple 的產品保證。

## 這台 Mac 的實際查核

本機是 Apple M2、16 GiB RAM、macOS 27.0（26A428）。僅讀取 Foundation Models 能力，沒有建立推論 session、送出提示、啟用 AI 或下載模型：

- `SystemLanguageModel.default.availability`：`unavailable(.modelNotReady)`。
- `supportsLocale(Locale(identifier: "zh_TW"))`：`true`。
- 不可用狀態下讀出的 `contextSize` 為 0；這不是模型實際 context 上限為 0 的證據。

所以硬體／系統符合門檻，**目前模型尚未就緒**。此狀態不能單獨區分資產未完成準備與其他系統原因。證據：[唯讀能力查核](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/apple-ai-research/local-availability.json)、[查核程式](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/apple-ai-research/check-availability.swift)。

## 效能與相容性設計

鍵盤事件路徑保持固定規則。AI 放在使用者明確呼叫的非同步工作中，限制同時工作數、輸入長度與結果大小；可取消、可逾時，完成後釋放 session。使用者沒有操作時，不讀取剪貼簿、不掃描畫面、不預熱模型。

現有 App 的最低 macOS 14 支援保留：以系統版本及模型可用性顯示功能，較舊系統繼續使用規則預覽、校準及 OCR。按需執行可以控制本 App 的持續開銷；Apple 仍自行管理共享模型、快取與系統記憶體，不能承諾 API 呼叫後整台電腦的模型記憶體立即歸零。另需針對 OS 模型更新維護提示與實際品質測試。
