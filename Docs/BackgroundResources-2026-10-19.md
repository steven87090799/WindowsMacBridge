# 背景 CPU、記憶體與液態玻璃資源研究

2026-10-19。結論：專案已有低背景負載的設計，這次實測也沒有發現持續忙迴圈或明顯記憶體增長。主程式加 Finder 擴充的 footprint 約 **80 MiB**，主程式背景平均 CPU 約 **0.003% 單核心**。這不等於零資源，也不能宣稱已達所有情境的最佳值。可見液態玻璃的 GPU 成本仍未量化。

## 版本、方法與範圍

- 本機為 Apple M2、16 GiB、8 邏輯核心、macOS 27.0（26A428）；候選程式以 Swift 6.4、Release 建置。
- 安裝位置 `/Applications/WindowsMacBridge.app` 是 **0.6.0 build 54**，revision `b25e8e8ade88996cd91e67da53b2575a9d9e3e44`。被動觀察使用精確執行路徑，未重新啟動或更換 App。主程序當時已存活約 20 小時；本次觀察只有五分鐘，不能稱為 20 小時測試。
- 液態玻璃 **build 55** 基準為 `ef687b178049733cde717a1276c7679497dd1a5a`，仍在 [PR #17](https://github.com/steven87090799/WindowsMacBridge/pull/17)。本輪新增診斷與 CI，並把原有的兩行關閉釋放動作抽成共用函式；沒有改鍵盤翻譯策略。build 55 未安裝。
- build 54：既有 `monitor-runtime.py` 每 15 秒取樣，共 21 筆／程序，起訖執行 `vmmap -summary`。另外以核心資源計數器，每 30 秒取樣、共五筆，核對 PID 與 process birth，計算約 120 秒的精細 CPU／wakeups／I/O 差值。
- CPU 百分比是 `CPU 秒差 ÷ 實際經過秒數 × 100`，單核心滿載為 100%。沒有用程序整個存活期間的平均百分比代替本輪負載。
- 註冊資訊顯示主程序有三個 enabled Event Tap，三者均含完整鍵盤事件 mask；這只確認註冊狀態。沒有讀取鍵盤事件內容、使用者畫面、一般剪貼簿或文件。
- 原始 CSV、JSON、取樣堆疊及測試日誌留在本機 `build/resource-study-20261019/`。可攜的數據、限制與量測來源檔 SHA-256 見 [機器清單](BackgroundResources-2026-10-19.json)。

## 安裝版背景實測

| 指標 | 主程式 build 54 | Finder 擴充 |
| --- | ---: | ---: |
| 五分鐘 CPU 秒增量（ps 精度 0.01 秒） | 約 0.01 秒 | 0.00 秒 |
| 精細取樣期間 | 120.049 秒 | 120.051 秒 |
| 精細 CPU 秒增量 | 0.003791 秒 | 未增加 |
| 平均 CPU，單核心 100% | **0.00316%** | 計數器未測得增量 |
| 起訖 physical footprint | **72.142 → 72.142 MiB** | **7.844 → 7.844 MiB** |
| 五分鐘 RSS 範圍 | 27.34–33.81 MiB | 16.27–17.84 MiB |
| 120 秒 interrupt wakeups 增量 | 40（約 0.33 次／秒） | 0 |
| 120 秒 package-idle wakeups 增量 | 2 | 0 |
| 120 秒核心歸帳磁碟讀／寫增量 | 0／0 bytes | 0／0 bytes |

五分鐘 `vmmap` 的主程式 footprint 同為 72.1M；Finder 是 8001K → 8033K。主程式本次存活期間的 footprint 高水位為 83.86 MiB，Finder 為 10.67 MiB；兩個各自高水位不能相加為同時峰值。

RSS 反映當下 resident pages，footprint 另有私有、壓縮等記憶體歸帳，兩者不是同一個指標。不能因為 RSS 降低就宣稱已釋放相同數量的配置，也不能把整台 Mac 的 swap 算成本程式消耗。不同程序的共享頁也會影響 RSS 的直接相加。

觀察結束後另做兩秒、10ms 間隔的堆疊取樣：主執行緒、NSEvent 執行緒及 `WindowsMacBridge.Input` 均在 RunLoop／Mach message 等待；沒有在這份樣本看到忙迴圈。這是有限時間的佐證，不能涵蓋每個背景狀態。

這輪是現有工作環境中的背景觀察，並未安排實體鍵盤負載、遠端連線、睡眠喚醒、Secure Input 或進階 HID 的控制實驗。不可把它當成這些情境的效能驗收。

## 已確認的程式設計

| 路徑 | 觸發與資源管理 | 評估 |
| --- | --- | --- |
| `BridgeCore/RuntimePolicy.swift`、`WindowsMacBridge/BridgeController.swift` | 沒有明確暫停／診斷／校準期限時，`RuntimeWakePlan` 為 stopped；需要時只建立單次 timer | 無一般閒置定時輪詢 |
| `BridgePlatform/InputEngine.swift` | 專用 RunLoop 等輸入；callback 後合併維護，純計數變動不喚醒整個 MainActor／設定頁。按鍵期間權限檢查節流，Secure Input 安全檢查仍保留 | 背景等待；打字仍需要 CPU，不能承諾零成本 |
| `WindowsMacBridge/AppMain.swift` | 狀態列圖示與 tooltip 只在內容改變時更新；設定視窗按需建立。關閉時清除 hosting controller、content view、delegate 與持有者 | 沒有永久設定頁刷新或狀態動畫 |
| `BridgePlatform/RemoteInputAdapters.swift` | App 啟動／觀察到來源才探索；最多 32 個來源，以 process-exit dispatch source 撤銷來源，停止時取消 | 沒有定時掃整張程序表 |
| `InputSourceSupport/GuardController.swift` | TIS／Workspace 通知；啟動、校正與 Secure Input 恢復使用有界重試。Secure Input 等待跑完退避序列後停止 | 異常恢復可能短暫喚醒；不應移除安全邏輯 |
| `BridgePlatform/NativeScreenshotObserver.swift` | 相容路徑使用 FSEvents，有限候選佇列與去重；停止時關閉 stream | 事件驅動，非資料夾輪詢；本輪未啟動相容截圖觀察 |
| `BridgePlatform/ScreenshotManager.swift`、`ScreenshotCaptureDriver.swift` | 一次一個工作；單次逾時，取消／完成清理。一般 PNG fast path 不完整解碼再重編碼 | 正常待命沒有圖片工作；截圖時仍有暫態配置 |
| `WindowsMacBridge/ScreenshotThumbnailPresenter.swift`、`GlassTheme.swift` | 成功複製後才建立 320×248 縮圖；長邊最多 720px／PNG 最多 1 MiB，約五秒到期。清空視圖並關閉 panel；Quick Look 僅在點擊後啟動並追蹤自己的程序 | 小圖與單次計時，沒有常駐玻璃 panel；1 MiB 不是整個 UI 記憶體上限 |
| `BridgePlatform/ScreenshotTextWorkerClient.swift`、`Tools/OCRWorker` | 明確文字擷取才啟動 worker；完成退出，逾時取消後有終止上限；主程式不直接連結 Vision | OCR 計算與模型不由主程式主動常駐／預熱 |
| `Extensions/FinderSync/FinderSync.swift` | 通知握手；`directoryURLs = []`，沒有全磁碟觀察。只在使用選單時取得所需路徑 | 擴充自身仍有約 7.8 MiB footprint |
| `BridgeCore/BoundedDiagnosticLogger.swift` | 128 slots／64 KiB pending、20 messages/sec、單一 drain，沒有輪詢 timer；檔案輪替 | 日誌不會無界累積在 RAM |
| `Tools/HIDBackend/Sources/HIDRuntime` | IOHID／XPC 事件；只有 held output／未完成回報才安排安全 deadline；無 client 時有單次 idle-exit | 這是來源檢查，非本輪進階後端實測 |

Finder 檔案剪下確認的 20ms 等待、結束 App 時還原鍵盤的 50ms 等待，均在明確操作內有次數／期限上限，不是常態背景輪詢。不能為了壓低喚醒數移除這些輸入與還原保護。

一般圖片輸入仍容許 64 MiB 檔案、最多 3600 萬像素／144 MiB 解碼預算；格式轉換還可能同時有輸入、輸出、codec 與剪貼簿配置。以上是個別資料的預算，不是全程序的硬性峰值。大圖操作可能顯著高於約 80 MiB 的背景基準。

## build 55 的關閉生命週期檢查

新增明確執行才啟用的 `--ui-resource-check <new-json-file>`。不啟動 `BridgeController`、不顯示視窗、不讀取輸入／畫面／剪貼簿。使用真正的 `SettingsWindowFactory`、原生側欄與合成表單，以及真正的 `ScreenshotThumbnailView`／`BridgeGlassPanelView`。

- 設定視窗 33 次、縮圖 panel 33 次；追蹤 window、hosting controller、hosting view、panel、玻璃及縮圖視圖共 **198 個 weak reference，最後全部 nil**。
- 暖機關閉後的 30 秒 CPU 約 **0.00295% 單核心**。這是 UI 診斷程序，沒有正式輸入引擎，不能拿來宣稱完整 build 55 比 build 54 節省多少。
- 暖機關閉 footprint 33.079 MiB，30 秒後 31.110 MiB，三批完成後 31.517／31.642／31.673 MiB，最後 31.626 MiB。這是有限批次下的小幅變動，沒有證明永久不洩漏；框架及 allocator 快取也不會因每次 close 都回到未開窗基準。
- 已把同一份物件釋放檢查加入 CI；只對殘留物件判失敗，不用受 runner 波動影響的固定 CPU／RAM 數字當硬門檻。CI 的 macOS 15 會測 fallback material，本機 macOS 27 才涵蓋原生玻璃分支。

本輪把正式關閉與診斷使用的相同釋放流程集中在 `SettingsWindowFactory.releaseContent(of:)`，以降低未來修改其中一邊而失去保障的風險。沒有增加日常背景取樣或監測 timer。

## OCR 與框架載入的重要界線

本輪再次確認：`--resource-self-check` 的無 GUI 啟動約 2 MiB，沒有 Vision／CoreML；但只初始化 `NSApplication`、尚未建立設定視窗的合成程序就已間接載入 Vision／CoreML，完整已安裝 App 的 binary-image 清單也有它們。主程式 `otool -L` 沒有直接連結這兩個框架。

所以「OCR 在獨立程序」不等於「macOS GUI 永遠不會映射 OCR 相關系統框架」。載入框架也不等於模型常駐、正在辨識或使用同等大小的私有 RAM；不可將 shared-cache 映射大小直接算成 App 的獨占用量。

另外用自產 `SCREEN TEXT 123` 圖片執行三次真正 worker：

| 項目 | 本次結果 |
| --- | ---: |
| 三輪完成時間 | 24.030／0.428／0.245 秒 |
| 三輪 worker 的最大 RSS 高水位 | 222.67 MiB |
| IPC 診斷父程序 footprint | 5.20 → 4.78 MiB |
| 結束後本檢查的 worker 數 | 0 |

worker 使用已驗證 build 55 CI 產物，revision `0e4e839881e27e18574f25ad27952c0a701e026f`。這個合成 merge tree 與 UI 基準 head 相同。未清除系統模型快取，因此第一輪不能稱為嚴格冷啟動；24 秒仍證明首次使用延遲尚存在。這次未拆解該時間的 CPU／GPU／等待比例。RSS 是子程序高水位，父程序數字不包含 worker 與系統服務，也不代表完整 App 或全系統的峰值。

背景省資源與 OCR 首次快速啟動有取捨；現有設計優先不預熱、不常駐模型。辨識結束後 worker 退出，但系統自己的模型／檔案快取仍由 macOS 管理。

## GPU 判斷與後續優先順序

原生玻璃是動態材質，可見時需要系統合成，不能保證零 GPU。來源沒有自訂 Metal renderer、DisplayLink、TimelineView、repeatForever 或玻璃專用重繪 timer；設定關閉與縮圖到期後，不再持有這些玻璃視圖。狀態列圖示仍由系統顯示。

本機僅有 Command Line Tools，沒有 `xctrace`；`powermetrics --show-process-gpu` 回覆需要 superuser。本輪沒有提升權限。未取得有效的 per-app GPU trace，整個 WindowServer 的百分比也不能歸因於 WindowsMacBridge。離屏建立／釋放測試不能替代可見玻璃、滾動、動畫與背景變動的 GPU 測試。

建議按以下順序繼續：

1. 保持事件驅動、按需 UI／OCR、關閉釋放及新的 CI 保護。日常關閉設定視窗可移除該視圖樹；縮小或遮住視窗仍可保留設定 UI 狀態。
2. 若不使用 Finder 右鍵路徑選單，可由使用者選擇停用 Finder 擴充，減少它自身約 7.8 MiB 的 footprint；實際程序回收時機由系統決定。本輪保留其狀態。
3. 用 Instruments 在實機比較：設定未開啟、可見靜止、滾動、縮圖五秒及消失後的 GPU／能耗。再依證據決定是否需要更低成本材質選項。Apple 建議限制同屏玻璃效果數量並量測，不能從「原生」推論沒有成本。
4. 完整 build 55 的長時間 GUI／實體打字／遠端／睡眠恢復資源趨勢，仍需獨立驗收。本輪未發現需要犧牲鍵盤可靠性的大幅改寫依據。

## 驗證與重現

- Release 主程式與獨立 C 資源工具建置成功。
- 精細 CPU 工具已用自產約 0.75 秒 CPU 工作交叉核對：`getrusage` 0.750005 秒、工具 0.750898 秒；錯誤 executable 拒絕（65）、非法 PID 拒絕（64）。Apple silicon 的 Mach timebase 為 125/3，已換算；探索期未換算的輸出未納入結果。
- 引擎喚醒／縮圖／有界讀取 19 項通過；完整程序 footprint 回歸另外獨立執行一次通過；`RuntimeWakeRegressionTests` 通過。19 項中含同一 memory case，獨立執行是為排除其他 suite 的配置干擾，不計為新增測試。
- 原有 Release 純合成 routing-update benchmark（0／1／16 來源、每組三輪）通過；數據附機器清單。它測的是重用相同 routing configuration 的更新，不能當成真實鍵盤事件延遲。
- build 55 先前完整 Debug／Release 各 484 項、Installer 62、Monitoring 6 的 CI 結果屬於 UI 基準 head；本輪新增診斷後的最新 CI 必須以 PR 最新 head 為準。

```sh
# 使用開發建置或已包含新診斷的 App executable；不啟動正式引擎。
WindowsMacBridge --ui-resource-check /private/new-output.json

# 這個工具不打包進 App，只讀已存在的指定程序計數器。
clang -O2 -Wall -Wextra -Werror Tools/ResourceStudy/process-resource-snapshot.c -o /private/snapshot
/private/snapshot <pid> /Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge
```

Apple 依據：[減少 timer 喚醒](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)、[主動進入閒置而非依賴 App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)、[限制 Liquid Glass 效果並量測](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[分析記憶體用量](https://developer.apple.com/documentation/xcode/analyzing-memory-usage)、[Apple XNU 計數器實作](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c)。
