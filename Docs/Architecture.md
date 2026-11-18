# WindowsMacBridge 架構

App 在 macOS 選單列執行。預設由目前登入的使用者啟動 EventTap。進階 HID 在使用者明確選用並安裝之後，才透過授權的本機 XPC 連線，由背景服務擷取指定鍵盤並透過官方 VirtualHID 輸出。

```text
WindowsMacBridge App ── 設定 / 權限 / 前景 App / session
   │
   ├─ 一般模式：BridgePlatform InputEngine → BridgeCore 規則 → AppKit / CGEvent
   │                                      └→ 有界的剪貼簿、Finder、截圖工作
   ├─ 進階 HID：HIDBackendClient → 本機 XPC → WindowsMacBridge --hid-service
   │                                      → HIDRuntime / BridgeCore → VirtualHID
   └─ 輸入法：InputSourceCore → InputSourceSupport → macOS TIS / Carbon
```

## 原始碼入口

| 路徑 | 責任 |
| --- | --- |
| [Sources/WindowsMacBridge](../Sources/WindowsMacBridge) | `AppMain.swift` 選擇 GUI 與命令模式。控制器管理權限、設定、後端和復原，AppKit／SwiftUI 顯示選單、設定與規則預覽。 |
| [Sources/BridgeCore](../Sources/BridgeCore) | Windows 規則、按下／重複／放開配對、來源／目的地策略、Finder、文字導覽、遠端通道、HID 規則和純狀態模型。 |
| [Sources/BridgePlatform](../Sources/BridgePlatform) | EventTap、已驗證的遠端來源、滑鼠與鍵盤事件輸出、輸入監控與輔助使用、Finder／截圖工作及 HID client。 |
| [Sources/BridgeWorkGate](../Sources/BridgeWorkGate) | 跨執行緒的有界工作與撤銷機制。 |
| [Sources/HIDProtocol](../Sources/HIDProtocol) 與 [Tools/HIDBackend](../Tools/HIDBackend) | 本機 XPC 訊息、裝置／生命週期管理、官方 VirtualHID C ABI。root 服務是同一 App 二進位的 `--hid-service` 模式。 |
| [Sources/InputSourceCore](../Sources/InputSourceCore) 與 [Sources/InputSourceSupport](../Sources/InputSourceSupport) | 唯音／ABC 規則，以及 macOS TIS、Carbon 熱鍵和輸入法狀態協調。 |
| [Tools/RecoveryHelper](../Tools/RecoveryHelper) 與 [Resources/Installer](../Resources/Installer) | 異常結束後的有界復原、選配 HID 的安裝與回滾。 |
| [Tests](../Tests) 與 [scripts](../scripts) | Swift、Python 回歸，App 建置、封裝與驗證入口。[Build 指南](Build.md) |

同一份 [Package.swift](../Package.swift) 建置 App、HIDRuntime 和測試。開發 App 包含 FinderSync 擴充，但一般 Finder 快捷鍵無需開啟它。完整 ZIP 與 DMG 在 App 內附加選配的 HID 安裝材料，流程見 [HID 後端](../Tools/HIDBackend/README.md)。

## 修改輸入時要保留的契約

- 輸入執行緒使用最新的設定快照。合併喚醒後必須取到最新 mailbox revision。查詢程序、簽章或 AX 焦點等工作移出鍵盤回呼，晚到結果要確認來源、焦點及狀態仍有效。
- 按下、重複、放開的行為和來源綁定。切換 App、暫停、睡眠、撤權及遠端斷線要取消過時工作並保留安全的放鍵配對。修改規則時也要核對規則預覽和各輸入後端。
- Bridge 只在接收端辨識遠端來源。入站原始 Windows 組合、已是 Command 的組合、未知來源，以及送往 Windows／VM 的按鍵，各有自己的策略。
- 一般模式由使用者執行。進階 HID 服務只從 root 擁有的同簽章 App 副本啟動。切回一般模式需先確認已釋放鍵盤。
- 診斷用規則 ID、事件 metadata 與時間，請勿把實際鍵入文字或剪貼簿內容放進測試或回報。只有使用者觸發的複製、Finder 與截圖等功能使用系統剪貼簿。

Apple 螢幕共享／VNC 的維護規則見 [AGENTS.md](../AGENTS.md) 和[事件紀錄](ScreenSharingVNC-2026-10-24.md)。自動測試、包裝與簽章、系統權限、實體輸入分別驗證。歷史設計可從[原始 0.2 架構紀錄](https://github.com/steven87090799/WindowsMacBridge/blob/5f7089d6335737420c7825edcd90ef1a77d902a5/Docs/Architecture.md)和[歷史驗證](Validation.md)查閱。
