# WindowsMacBridge 0.2.0：唯音輔助整合

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
| 舊版 VChewingGuard 執行中 | 仍依 Windows Mode／Profile | 暫停，顯示衝突，不與舊程式爭奪來源 |

切換輸入來源前先發布 `selectionInProgress` 關閉新快捷鍵翻譯，等待 TIS 通知或驗證結果。TIS 通知會更新 keyboard layout cache；不再由 UI timer 每 0.5 秒查詢 TIS。返回 ABC 時，現有鍵盤引擎要求 modifier neutral 才接受新翻譯。TIS／Workspace 通知與鍵盤事件並非 macOS 原子交易，仍存在短暫通知競態，不能宣稱完整消除。

每次真正選擇來源，以及 Carbon hotkey callback，都再次檢查當下前景 Profile、暫停與舊版程序。NSWorkspace 快取僅供鍵盤 hot path 使用；昂貴的即時檢查位於低頻 TIS 操作前。切換到遠端時 Carbon unregister 依 Workspace 通知處理，通知到達前的極短期間仍可能吃掉已註冊組合，這是實機驗收項目。瀏覽器內遠端、Coherence、未知 Client 需使用者指定整個 App Profile。

## 設定、遷移與登入項目

- Windows 設定保留原 `bridge.settings.v1`；輸入法偏好及計數使用 `inputSource.*`，不改 Windows 設定 schema。
- 初次使用：Windows Mode、守護、全域切換快捷鍵均預設關閉，不自動啟動登入項目或要求 TCC。
- 唯音功能不需要 Accessibility。Windows 快捷鍵才需原有權限流程。
- 設定頁的「匯入舊版 VChewingGuard 偏好」只讀取 `com.local.VChewingGuard` domain 的 debounce、startup delay、hotkey preset；驗證型別、範圍與已知 preset。
- 不匯入 guard enabled、登入項目、舊日誌、使用歷史或任意其他 key。不清除舊偏好。
- 偵測到舊版執行時可按「結束舊版 VChewingGuard」正常要求它結束，不強制 kill。監聽 termination 後解除阻擋。
- 舊版的登入項目需在系統設定停用；目前 App 的 `SMAppService.mainApp` 不代替另一個 bundle 取消註冊。正式使用時把整合版放到固定 Applications 路徑，再設定一個登入項目。
- 唯音輸入法本體仍需另行安裝；整合的是輔助工具，不是重製或內嵌輸入法。

## 隱私與驗證邊界

沒有第二個 Event Tap、沒有剪貼簿讀取／匯出流程、沒有 Unicode 文字讀取、沒有網路或 telemetry。Carbon 只註冊使用者選定的一個切換組合，沒有全域逐鍵紀錄。

Windows 規則診斷維持 128 筆、5 分鐘、僅記憶體。唯音診斷計數和有限切換成功時間存於 UserDefaults；來源 ID、結果與系統狀態存於 `~/Library/Logs/WindowsMacBridge/InputSources.log`，512 KiB 輪替成一份 `.1`。不把鍵盤引擎事件交給這個 logger。只有使用者按「更新診斷」才讀取近期 log 到 UI，不自動複製到剪貼簿。

`--self-check` 驗證包內 App registry；`--diagnose-input-sources` 只列舉 TIS metadata，不選來源、不註冊 hotkey、不啟動 tap、不寫日誌。Unit tests、AppKit 程序內測試和 UI smoke 不等於真實遠端／IME／跨登入 session 驗收。
