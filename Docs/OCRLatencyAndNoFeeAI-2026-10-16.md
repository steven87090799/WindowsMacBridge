# OCR 延遲複測與免開發者年費的 AI 路線

日期：2026-10-16，Asia/Taipei。使用者不希望為本專案購買 Apple Developer Program，已有 iCloud+。本輪只做官方資料查核與生成圖片的離線量測，沒有申請方案、使用雲端推論、改變 Apple Intelligence 設定或更換已測的正式程式。

## iCloud+ 與 App API 是不同的資格

App 直接使用 PCC API，仍要符合 [Apple 官方的開發者資格](https://developer.apple.com/private-cloud-compute/)，包含 Small Business Program 及 PCC entitlement。iCloud+ 是使用者端額度方案，不能取代開發者資格。官方 [PCC 文件](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)說明使用者可透過 iCloud+ 取得較高額度。

不付開發者年費仍有可用路線：Apple 的[「捷徑」使用模型動作](https://support.apple.com/en-il/guide/shortcuts-mac/mchl91750563/10.0/mac/27)可以使用本機模型或 Apple 雲端模型。使用者自行建立／執行捷徑不需要加入 Developer Program；模型可用性、名稱及額度以系統顯示為準。這不等於讓本 App 自動取得直接呼叫 PCC 的 entitlement。

本專案未來可接一個使用者明確呼叫的流程：「OCR 複製文字 → 執行自己的捷徑 → 使用 Apple 雲端模型摘要／整理 → 顯示結果」。這是可行的整合方向，尚未實作，也沒有建立或執行任何讀取使用者剪貼簿的捷徑。本機 Vision OCR 本身不需要 PCC、iCloud+ 或付費 Developer Program。

## 原本 24 秒不是每次啟動的固定成本

對相同 build 50 產物重跑原本的三輪 worker 測試，結果為 **0.731／0.270／0.256 秒**。三輪都重新建立辨識子程序。這表示結束 worker 不必然讓下一次又等 24 秒，系統或模型的暖機狀態會影響結果。

再用新的獨立測量程式，將讀圖、解碼、建立 request、查詢語言與 `perform` 分開，重新觀察到一次 **23.712 秒** 的慢呼叫：

| 階段 | 秒 |
|---|---:|
| 讀取生成的 PNG | 0.000257 |
| 建立／解碼圖片 | 0.004833 |
| 建立及設定 request | 0.000246 |
| 查支援語言 | 0.005957 |
| Vision `perform` | **23.687377** |

可確認瓶頸在 Vision 內部，而不是檔案讀取或啟動擷取介面。首次模型載入、執行環境／模型準備、快取建立或系統等待都是可能因素；目前量測只到公開 API 邊界，沒有把 `perform` 裡的 23.7 秒進一步分解，因此不能斷言全是模型載入，也不能保證第一次永遠只要 0.7 秒。

## 加速方式的實際比較

共 24 輪辨識設定比較，加 12 輪計算裝置比較。所有圖片皆為程式產生，沒有讀取實際畫面、按鍵、視窗或剪貼簿。除下列單一設定差異外維持相同語言及圖片；數值只適用這個有限測試。

| 方案 | 繁中混合圖片暖機後兩輪的時間中位數 | 結果 |
|---|---:|---|
| 現行 accurate＋背景偏好 | 0.273 秒 | 繁中、英文與測試程式碼正確 |
| accurate＋取消背景偏好 | 0.275 秒 | 相同辨識結果，沒有看到加速 |
| fast、執行時支援清單過濾後只剩英文 | 0.127 秒 | 中文大幅遺失；測試程式碼也漏掉等號，不能作為目前繁中 OCR 的替代 |
| accurate、只選英文 | 0.189 秒 | 中文成為錯字或消失，不能作為繁中加速方式 |

英文圖片的 fast 模式暖機後約 0.118 秒，而現行 accurate 約 0.249 秒；未來可以考慮明確選擇「僅英文快速辨識」，但不是自動把所有使用者的辨識改為英文。

另以 Apple 公開的 compute-device API 選擇該請求主要計算階段支援的 CPU，第一次仍量到 `perform` **23.442 秒**，整體 **24.305 秒**；後續時間與自動選擇接近。這項測試不能支持「改 CPU 就能解決首次延遲」。

Apple 說明 [`preferBackgroundProcessing`](https://developer.apple.com/documentation/vision/vnrequest/preferbackgroundprocessing)是減少資源負擔的提示，可能用更長時間換取較少資源競爭；本機實測關閉後未見優勢，所以保留原設定。不同裝置仍可能有不同結果。

## 目前建議

保留準確模式與繁中／英文，按需執行、每次一個工作、完成後退出 worker。框選時縮小範圍與保持文字清楚，可以減少辨識工作；現行程式已限制辨識像素量。

預熱是另一個選項：先用生成圖片讓 Vision 做第一次準備，再等真正的 OCR。它會把成本移到較早時間，而不是消除成本，並需要額外 CPU／記憶體；因此沒有改成登入就預熱或常駐模型。可以在未來設計成明確的選用操作，但仍須量測其效益與取消／期限行為。

這輪沒有找到可同時保留繁中能力、消除首次初始化等待、又不增加背景成本的簡單開關。因此**正式程式維持原狀**；來源雜湊仍符合已通過 Debug／Release 各 465 項與 Python 68 項測試的版本，未宣稱這些是對實驗工具的新測試結果。

證據：[相同產物複測](/Users/steven/Documents/ChatGPT/我/build/ocr-latency-20261016/existing-worker-repeat.json)、[分段與模式比較](/Users/steven/Documents/ChatGPT/我/build/ocr-latency-20261016/stage-comparison.json)、[CPU 比較](/Users/steven/Documents/ChatGPT/我/build/ocr-latency-20261016/cpu-comparison.json)。獨立測量程式及生成圖片保存在同一資料夾，實驗工具未加入 App 包裝。
