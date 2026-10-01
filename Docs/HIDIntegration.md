# 0.5.14 HID 整合與驗收界線

本次完整修復與測試見 [PreReleaseRepair-2026-09-30](PreReleaseRepair-2026-09-30.md)。以下描述目前執行路徑，實體驗收尚未完成。

## 可建置的接線

```text
WindowsMacBridge Menu Bar / 唯音協調器 (console user)
  NSWorkspace / source / session -> cached EngineConfiguration
  backend = EventTap              backend = deviceHID
  InputEngine -> marked CGEvent   HIDBackendClient -> signed controller XPC
                                  root BridgeHIDHelper.app
                                  DeviceCapture -> IOHIDDevice per target
                                  HIDTranslationEngine -> HIDOutput
                                  VirtualHID C ABI -> official root daemon
                                  signed DriverKit -> virtual keyboard
                                  -> App
                                  fixed Finder/System action IDs -> user App
                                  -> bounded ShortcutActionDispatcher
```

主 App 不需要 root 執行。下載包含固定版官方 Driver/daemon package；自己的 helper 使用 root launchd。官方套件的 install、activation、daemon 必須依 [原廠使用流程](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ba98de7fae2d529b9debe82890765dc66246f4ff#usage) 完成。若已有不同共用 package 版本，安裝器停止，不降版。

0.4.1 新設定預設 `InputBackend.eventTap`、enabled=true、allKeyboards，並為 Codex 聊天／文字預設 macOS override；權限未授予仍不翻譯，損壞設定使用停用 fallback。所有已存設定保留，舊設定缺少後端欄位時保留 EventTap。HID 可選所有支援的簡單 keyboard descriptor 或內建／Apple 834 範圍；不支援／不接管的裝置保持原生，不建立無法辨識來源的 EventTap 混合翻譯。選 HID 時 EventTap 的翻譯與控制均 disabled。未啟用不建立 VirtualHID client；helper 可回報 metadata/status。

## 類別責任與 IPC

| 模組 | 責任 |
| --- | --- |
| BridgeCore/HIDTranslationEngine | 16 個 device ID、256 個 press slots；physical/consumed/output 分離；compiled rules；固定 32 usage/report；上下事件配對 |
| BridgeCore/HIDKeyMap | USB HID usage 與 Carbon virtual key position 表；不解碼文字／Unicode |
| HIDProtocol | ≤4096 byte config/status；版本、context、generation、restart、enable、heartbeat；固定 Finder/System action ID；明確權限 request |
| BridgePlatform/HIDBackendClient | main actor NSXPC；最多一筆 in-flight configure；每 250 ms heartbeat；超時／拒绝斷線；generation/PID 驗證動作 |
| HelperService | console UID + runtime SecCode validity + bundle identifier + root-owned CDHash pin；單一 controller；無 shell/key-stream endpoint |
| DeviceCapture | 單 CFRunLoop 的 IOHID callbacks、descriptor 篩選、neutral probe、seize、watchdog、report queue、context transition |
| HIDLifecycle | driver ready / lease / permissions / session / secure / neutral 狀態契約；partial open 也必定 cleanup |
| VirtualHID C ABI | SDK 的 keyboard/Fn/consumer/vendor/desktop report；只在 ready 時發送；256 outstanding、500 ms 無回覆失效 |
| Installer | root-owned app/helper/pin；固定 launchd 路徑；先 snapshot/hash/codesign 檢查；備份舊 App；停止／移除自己註冊 |

單一 controller 接受其編譯版本的政策；不接受任意 shell、路徑、按鍵 report 或 clipboard。NSXPC validate 根據 console euid 與 runtime code pin，並在每次 configure 再確認 console UID；Fast User Switching 不沿用前位使用者 lease。Pin 來自安裝後 App，更新需重新安裝並視 TCC 狀態重新授權。沒有 Developer ID 時此 pin 只保證已安裝二進位身分，不代表 publisher 公證。

callback 不查 NSWorkspace、AX、JSON、檔案或網路；只讀已編譯 policy、physical usage、secure-input flag、單調時間，更新有限 ownership，enqueue report／最多16筆 action。SDK 仍有小量 report allocation，因此尚未量測前不宣稱 <1 ms。HID 短期診斷只有固定 rule ID、計數與最大 callback 處理時間；不記錄 ordinary characters。

## 狀態與原始規則

開啟觀察前要求 enabled、session、permission、controller lease、virtual keyboard ready。非獨占觀察確定 neutral，再 close/reopen seize，seize 後立刻再次 probe；gap 內有鍵按下時 partial cleanup 並要求重啟。加入／移除支援服務會停止當前擷取，等所有鍵 neutral 再接管。未知 descriptor 不擷取；避免把 mouse/multitouch 或非鍵的 axis 當成鍵盤。

#4 對應 builtIn 或 keyboard VID1452/PID834；#5–10 依保存的 Win 鍵位置及 MacBook Fn／Ctrl 開關配置：只有標記為內建且開關啟用的服務交換 Fn／左 Ctrl，Win=Command 才交換接管裝置的 Option／Command。#13–60 及 Finder／文字／Alt+F4／Win+R/I/Tab 開關由版本 3 的 helper IPC 傳入。規則根據實體 Win／Alt 位置及已選的 Fn／Ctrl 模式匹配，輸出不再匹配，避免複雜規則遞迴。每個 active shortcut 綁定來源裝置與 modifier contributor；只在該 shortcut active 時消耗輸出，key-up 後恢復仍按住的實體 modifier。新 chord 與旧輸出不相容時先釋放舊輸出，不混合 Command／Option。兩種 Win 配置下，實體 Alt+Tab 均輸出原生 Command+Tab 並持有 Command 至 Alt 放開。Fn 使用 Apple top-case report，不偽裝成 CGEvent modifier。

#61–76 經固定 action IPC 到現有 Finder dispatcher；沒有 clipboard payload 進 helper。#77 預設關閉，只在獨立開關、Finder 增強與本機 Finder 情境同時成立時轉換 consumer brightness increment 0x6f；其他支援 consumer/top-case/vendor/desktop usage 保持各自 report。#11 左 Option+L 是 HID keyboard chord，#12/#78 是固定系統 App 動作。

Remote／VM／Game／Disabled 與未支援來源直接交回原生實體 HID，避免破壞 Client 的獨占／指定裝置輸入。這時不在原生流攔截右 Option+P／緊急熱鍵，改用 Menu Bar；不同於原始 #1 的全情境攔截。返回本機需 neutral 後才接管。

以下是有意保留的差異：Terminal/IDE 整個 HID passthrough，保護 Unix 和內嵌 terminal，原 JSON 只有一般 Ctrl rule 排除；manual passthrough 同時涵蓋 consumer，原 JSON 的 any:key_code 無法完整停用 consumer；Finder 未確認檔案焦點時不猜移動／改名。這些差異不能稱為原 Karabiner 行為逐位元等價。

Context/PID/mode/layout/finder 或 restart 改變時先 invalidation；所有已輸出鍵/修飾鍵釋放，舊 physical holds suppress 至完全 neutral。模型的舊 hold 會 suppress；實際 Remote adapter 交回原生硬體，返回本機需 neutral，再接管，避免把旧的虛擬 Command 帶入 Remote。前景資料來自 user App 通知＋heartbeat，不是與 HID 原子同步；多媒體／fullscreen Client 特性仍需實測。

## 停止路徑

Lease 最多1秒、enabled-only timer 250 ms，connection invalidation、session、secure、撤權、driver not ready、output response 停滯500 ms、隊列 overflow 或 emergency 都觸發 reset outputs → close seized devices。close 不依賴 reset 成功。send/report fault 與 partial seize 要求 UI 明確 restart；不無限重試擷取。SIGTERM 先 stop/reset 再退出。SIGKILL/崩潰仰賴 OS 關閉 IOHID handle 與官方服務移除 client；實際 release timing 未驗收，不保證瞬時無卡鍵。

`Stop.command` bootout helper；`Uninstall.command` 只移除此工具的 helper/pin/launchd，保留 App、設定、備份與官方共用 Driver。Installer 本身未在開發機以管理員執行。

## Release gate

離線測試通過並不滿足正式替代的 P0 gate。仍須兩個實體鍵盤、ANSI/ISO、USB/Bluetooth、Magic Keyboard、Fn/Globe／Caps Lock LED／IME、sleep/session/撤權、seize gaps、driver stall/kill、helper/App kill、長期 latency/CPU/footprint 與每個 Remote Client 的功能矩陣。VirtualHID country US 與 geometry 也需驗收；不支援的 layout 停止翻譯，不代表已驗證所有 physical passthrough 語意。

正式版還需要自己的 Developer ID / notarization 與 root IPC 安全審查。此0.4下載是可安裝的整合測試包；尚不能承諾移除 Karabiner 後所有 78 規則在你的硬體上都通過。

## 世代、截圖與交接

統一 runtime snapshot 與 IPC generation 驗證所有回覆／動作。HID 提供四組 screenshot shortcuts，無第二套截圖 EventTap；所有 App policy 失效立即取消工作。HID → EventTap 先送 stop，收到 physical close／VirtualHID teardown 回覆才解除 ownership gate。1.5 秒 timeout 顯示錯誤並保持新後端停用，不能以逾時推定已釋放。這不是 Driver 實際送達 acknowledgement，需實機測失聯／kill。
