# WindowsMacBridge 0.5.6：唯音輔助整合

## 主專案與來源

後續開發集中在 `steven87090799/WindowsMacBridge`。只有一個 executable、`.app`、bundle ID（`local.WindowsMacBridge`）、Menu Bar、設定視窗與可選的 `SMAppService.mainApp` 登入項目。

輸入法模組來自 `steven87090799/vchewing-input-helper` 的 `43779320c58405e299a8da9afe7845f4d6c71e08`。保留狀態機、TIS discovery、三次有界重試、400 ms 驗證、Secure Input 退避、sleep/session 暫停、10 次／60 秒衝突冷卻與診斷計數。MIT 授權保留於 `Resources/Licenses/VChewingGuard.txt`，打包時一併放入 App。

沒有匯入第二個 AppDelegate、Menu Bar、設定視窗、@main 或獨立 executable。原 repository 保留歷史，未刪除或封存。

## 模組與執行緒

```text
WindowsMacBridge executable (Swift 6 / MainActor)
  AppDelegate: one NSStatusItem, settings window, process lock
  BridgeController: workspace lifecycle, app profiles, global pause
       |                         |
       | EngineConfiguration     | InputSourcePolicy + live pre-selection gate
       v                         v
  BridgePlatform             InputSourceSupport (Swift 5 adapter)
  dedicated input thread     InputSourceCoordinator (@MainActor public API)
  CGEventTap                 GuardController / InputSourceManager / Carbon hotkey
       |                         |                   |
       v                         v                   v
  BridgeCore                 InputSourceCore      TISSelectInputSource
  keyboard state/rules       GuardStateMachine    (main queue, never tap callback)
       |                         |
       +------- status ----------+
                 |
          unified SwiftUI / diagnostics
```

`BridgeCore` 與 `InputSourceCore` 沒有 AppKit／Carbon。既有鍵盤引擎維持 Swift 6 strict concurrency；移植的 Carbon/TIS adapter 暫時保留上游 Swift 5 language mode，所有可變守護狀態由 main queue 操作，公開入口由 `@MainActor` 限制，檔案日誌使用獨立 serial queue。沒有用 `@unchecked Sendable` 包裝整個守護程式。後續可逐步將 adapter 遷移至完整 Swift 6 檢查。

## 交界規則

| 狀態 | Windows 快捷鍵 | 輸入法守護、手動選擇、Carbon 切換鍵 |
|---|---|---|
| macOS App + ABC/U.S. | 依 Windows Mode 設定翻譯 | 依各自設定 |
| 唯音或其他中文 IME | 原樣通過 | 依守護／手動選擇設定 |
| Terminal / IDE | 原樣通過 | 允許本機輸入法守護 |
| Remote / VM / Game / Disabled | 原樣通過 | 取消待處理選擇並解除切換鍵註冊 |
| 暫停全部／緊急暫停 | 停止新翻譯；保留既有 pairing 邊界 | 取消工作並解除切換鍵註冊 |
| Secure Input | 停止翻譯 | 不呼叫 TIS selection，使用有界退避等待 |
| sleep / screen sleep / inactive user session | 暫停 | 暫停；全部 suspension reason 解除才恢復 |

切換輸入來源前先發布 `selectionInProgress` 關閉新快捷鍵翻譯，等待 TIS 通知或驗證結果。TIS 通知會更新 keyboard layout cache；不再由 UI timer 每 0.5 秒查詢 TIS。返回 ABC 時，現有鍵盤引擎要求 modifier neutral 才接受新翻譯。TIS／Workspace 通知與鍵盤事件並非 macOS 原子交易，仍存在短暫通知競態，不能宣稱完整消除。

0.5.3 保守保留所有外部來源變更。`preservedSelection` 取消 state machine 的重試交易；adapter 同時取消 debounce、verification、startup、Secure Input 意圖與衝突冷卻。TIS 通知不提供發起者，不能可靠區分手動與系統切換；即使外部選回前一來源、而本程式確認尚未到達，也優先取消待處理請求。啟動／喚醒／恢復採用實際當前 TIS 來源，只有本程式的明確請求釋放保留狀態。通知只讀來源 metadata，沒有新增逐鍵觀察。

輸入法偵測暫停使用 `GuardDetectionPause` 的絕對 Date／indefinite，持久保存在 `inputSource.pause*`；到期用一個可取消的 DispatchWorkItem 與 generation 驗證，重新啟動／喚醒會檢查是否已到期。沒有倒數 timer 或額外輪詢。這與原本停止全部快捷鍵的 global pause 分開，原本 Profile／pass-through／Event Tap callback 不變。

每次真正選擇來源，以及 Carbon hotkey callback，都再次檢查當下前景 Profile 與暫停狀態。NSWorkspace 快取僅供鍵盤 hot path 使用；昂貴的即時檢查位於低頻 TIS 操作前。切換到遠端時 Carbon unregister 依 Workspace 通知處理，通知到達前的極短期間仍可能吃掉已註冊組合，這是實機驗收項目。瀏覽器內遠端、Coherence、未知 Client 需使用者指定整個 App Profile。

## 設定、遷移與登入項目

- Windows 設定保留原 `bridge.settings.v1` key，schema v2 可移轉 v1；輸入法偏好及計數使用 `inputSource.*`。
- 初次使用：Windows Mode 與截圖自動複製預設開啟；唯音守護、全域切換快捷鍵預設關閉。截圖功能註冊登入項目；授權清單顯示原生檢查結果。
- 唯音功能不需要 Accessibility。Windows 快捷鍵才需原有權限流程。
- 本版本直接使用自己的輸入法偏好；舊版助手程序偵測、避讓、結束與偏好匯入已移除。正式使用時把 App 放到固定 Applications 路徑，再設定一個登入項目。
- 統計單獨接續：`InputSourceStatisticsStore` 首次從 `com.local.VChewingGuard` 的六個 `diagnostics.*` 欄位合併計數、日期與最多 20 筆去重紀錄，使用完成標記避免重複。不讀用戶輸入、不匯入舊偏好、不依賴舊程式是否安裝或執行。原有 `inputSource.diagnostics.*` 計數鍵保留；不需要更改 Windows Settings schema。
- 唯音輸入法本體仍需另行安裝；整合的是輔助工具，不是重製或內嵌輸入法。

## 隱私與驗證邊界

沒有第二個 Event Tap、沒有剪貼簿讀取／匯出流程、沒有 Unicode 文字讀取、沒有網路或 telemetry。Carbon 只註冊使用者選定的一個切換組合，沒有全域逐鍵紀錄。

Windows 規則診斷維持 128 筆、5 分鐘、僅記憶體。唯音診斷計數和有限切換成功時間存於 UserDefaults；來源 ID、結果與系統狀態存於 `~/Library/Logs/WindowsMacBridge/InputSources.log`，512 KiB 輪替成一份 `.1`。不把鍵盤引擎事件交給這個 logger。只有使用者按「更新診斷」才讀取近期 log 到 UI，不自動複製到剪貼簿。

`--self-check` 驗證包內 App registry；`--diagnose-input-sources` 只列舉 TIS metadata，不選來源、不註冊 hotkey、不啟動 tap、不寫日誌。Unit tests、AppKit 程序內測試和 UI smoke 不等於真實遠端／IME／跨登入 session 驗收。
