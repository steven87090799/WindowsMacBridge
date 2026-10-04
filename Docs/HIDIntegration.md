> 0.6.0 起 HIDRuntime 與 GUI 編譯成同一個 WindowsMacBridge executable。Input Monitoring 使用單一 App ID；root launchd 僅執行 `/Library/Application Support/WindowsMacBridge/WindowsMacBridge.app` 的唯讀、同簽章副本與 `--hid-service`。不執行使用者可替換的 Applications 副本。舊 HIDHelper Mach label 僅保留為內部 IPC 相容名稱；舊獨立 Helper App 在交易成功時移除，失敗時還原。Driver 保留官方簽章，不能假改 macOS 核准名稱。

# 0.5.15 HID 整合與驗收界線

本次來源分流、schema 5、protocol 4 與測試見 [UnifiedInput-2026-10-01](UnifiedInput-2026-10-01.md)；前批修復見 [PreReleaseRepair-2026-09-30](PreReleaseRepair-2026-09-30.md)。實體驗收尚未完成。

## 可建置的接線

```text
WindowsMacBridge Menu Bar / 唯音協調器 (console user)
  NSWorkspace / source / session -> cached EngineConfiguration
  backend = EventTap              backend = deviceHID
  InputEngine -> marked CGEvent   HIDBackendClient -> signed controller XPC
                                  WindowsMacBridge --hid-service
                                  DeviceCapture -> IOHIDDevice per target
                                  HIDTranslationEngine -> HIDOutput
                                  VirtualHID C ABI -> official root daemon
                                  signed DriverKit -> virtual keyboard
                                  -> App
                                  fixed Finder/System action IDs -> user App
                                  -> bounded ShortcutActionDispatcher
```

主 App 不需要 root 執行。下載包含固定版官方 Driver/daemon package；同一 App 的背景模式使用 root launchd。官方套件的 install、activation、daemon 必須依 [原廠使用流程](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ba98de7fae2d529b9debe82890765dc66246f4ff#usage) 完成。若已有不同共用 package 版本，安裝器停止，不降版。

0.5.15 新安裝預設 Device HID、enabled=true、allKeyboards，保留 Control 與 Fn／Globe。舊版明確 backend／鍵位選擇保留，缺 backend 欄仍保留 EventTap。Native Mac 偏好只交回對應實體服務，其他裝置保留 hold。HID 與同一個 session EventTap 的 remote 路徑並存，但 tap 不處理 hardware／UC／自身 output；未知 descriptor 不接管。未啟用不建立 VirtualHID client。

## 類別責任與 IPC

| 模組 | 責任 |
| --- | --- |
| BridgeCore/HIDTranslationEngine | 16 個 device ID、256 個 press slots；physical/consumed/output 分離；compiled rules；固定 32 usage/report；上下事件配對 |
| BridgeCore/HIDKeyMap | USB HID usage 與 Carbon virtual key position 表；不解碼文字／Unicode |
| HIDProtocol | config ≤8192 bytes／status ≤16384 bytes；版本（目前 IPC protocolVersion 7）、context、generation、actionGeneration、restart、enable；最多16裝置偏好／狀態，固定 Finder/System action ID；明確權限 request |
| BridgePlatform/HIDBackendClient | main actor NSXPC；最多一筆 in-flight configure；沒有 heartbeat，連線本身就是 ownership lease；超時／拒絕斷線；generation/PID 驗證動作；stop 逾時鎖定 releaseUnconfirmed |
| HelperService | console UID + runtime SecCode validity + bundle identifier + root-owned CDHash pin；另以 `setCodeSigningRequirement` 對每則訊息驗 audit token；單一 controller；無 shell/key-stream endpoint |
| DeviceCapture | 單 CFRunLoop 的 IOHID callbacks、descriptor 篩選、neutral probe、seize、watchdog、report queue、context transition |
| HIDLifecycle | driver ready / lease / permissions / session / secure / neutral 狀態契約；partial open 也必定 cleanup |
| VirtualHID C ABI | SDK 的 keyboard/Fn/consumer/vendor/desktop report；只在 ready 時發送；256 outstanding、500 ms 無回覆失效 |
| Installer | root-owned App/runtime/pin；固定 launchd 路徑；先 snapshot/hash/codesign 檢查；備份舊 App；停止／移除自己註冊 |

單一 controller 接受其編譯版本的政策；不接受任意 shell、路徑、按鍵 report 或 clipboard。NSXPC validate 根據 console euid 與 runtime code pin，並在每次 configure 再確認 console UID；Fast User Switching 不沿用前位使用者 lease。Pin 來自安裝後 App，更新需重新安裝並視 TCC 狀態重新授權。沒有 Developer ID 時此 pin 只保證已安裝二進位身分，不代表 publisher 公證。

callback 不查 NSWorkspace、AX、JSON、檔案或網路；只讀已編譯 policy、physical usage、secure-input flag、單調時間，更新有限 ownership，enqueue report／最多16筆 action。SDK 仍有小量 report allocation，因此尚未量測前不宣稱 <1 ms。HID 短期診斷只有固定 rule ID、計數與最大 callback 處理時間；不記錄 ordinary characters。

## 狀態與原始規則

開啟觀察前要求 enabled、session、permission、controller lease、virtual keyboard ready。非獨占觀察確定 neutral，再 close/reopen seize，seize 後立刻再次 probe；gap 內有鍵按下時不保留擷取。新增／重新啟用服務只等自己的 neutral，移除服務只清掉自己的 contributor；最後被接管的服務離開才停止整體 lifecycle。未知 descriptor 不擷取，避免把 mouse/multitouch 或 axis 當成鍵盤。

#4 對應 builtIn 或 keyboard VID1452/PID834；#5–10 依保存的 Win 鍵位置及 MacBook Fn／Ctrl 開關配置：只有標記為內建且開關啟用的服務交換 Fn／左 Ctrl，Win=Command 才交換接管裝置的 Option／Command。#13–60 及 Finder／文字／Alt+F4／Win+R/I/Tab 開關由版本 4 的 背景模式 IPC 傳入。規則根據實體 Win／Alt 位置及已選的 Fn／Ctrl 模式匹配，輸出不再匹配，避免複雜規則遞迴。每個 active shortcut 綁定來源裝置與 modifier contributor；只在該 shortcut active 時消耗輸出，key-up 後恢復仍按住的實體 modifier。新 chord 與旧輸出不相容時先釋放舊輸出，不混合 Command／Option。兩種 Win 配置下，實體 Alt+Tab 均輸出原生 Command+Tab 並持有 Command 至 Alt 放開。Fn 使用 Apple top-case report，不偽裝成 CGEvent modifier。

#61–76 經固定 action IPC 到現有 Finder dispatcher；沒有 clipboard payload 進背景模式。#77 預設關閉，只在獨立開關、Finder 增強與本機 Finder 情境同時成立時轉換 consumer brightness increment 0x6f；其他支援 consumer/top-case/vendor/desktop usage 保持各自 report。#11 左 Option+L 是 HID keyboard chord，#12/#78 是固定系統 App 動作。

Remote／VM／Game／Disabled 與未支援來源直接交回原生實體 HID，避免破壞 Client 的獨占／指定裝置輸入。這時不在原生流攔截右 Option+P／緊急熱鍵，改用 Menu Bar；不同於原始 #1 的全情境攔截。返回本機需 neutral 後才接管。

以下是有意保留的差異：Terminal/IDE 整個 HID passthrough，保護 Unix 和內嵌 terminal，原 JSON 只有一般 Ctrl rule 排除；manual passthrough 同時涵蓋 consumer，原 JSON 的 any:key_code 無法完整停用 consumer；Finder 未確認檔案焦點時不猜移動／改名。這些差異不能稱為原 Karabiner 行為逐位元等價。

Context/PID/mode/layout/finder 或 restart 改變時先 invalidation；所有已輸出鍵/修飾鍵釋放，舊 physical holds suppress 至完全 neutral。模型的舊 hold 會 suppress；實際 Remote adapter 交回原生硬體，返回本機需 neutral，再接管，避免把旧的虛擬 Command 帶入 Remote。前景資料來自 user App 通知＋heartbeat，不是與 HID 原子同步；多媒體／fullscreen Client 特性仍需實測。

## 停止路徑

Ownership 由已驗證的 XPC 連線維持（沒有 heartbeat 或固定 timer；持鍵時才有單次 1 秒安全檢查）。connection invalidation、console 使用者改變（configd 通知）、session、secure、撤權、driver not ready、output response 停滯500 ms、隊列 overflow 或 emergency 都觸發 reset outputs → close seized devices，並立即發布狀態。close 不依賴 reset 成功。Secure Input／session 屬暫時狀態，釋放後可重新擷取；send/report fault 與 open 失敗要求 UI 明確 restart；observe→seize 之間按鍵最多重試 3 次。不無限重試擷取。SIGTERM 先 stop/reset 再退出。SIGKILL/崩潰仰賴 OS 關閉 IOHID handle 與官方服務移除 client；實際 release timing 未驗收，不保證瞬時無卡鍵。

`Stop.command` bootout helper；`Uninstall.command` 只移除此工具的 helper/pin/launchd，保留 App、設定、備份與官方共用 Driver。Installer 本身未在開發機以管理員執行。

## Release gate

離線測試通過並不滿足正式替代的 P0 gate。仍須兩個實體鍵盤、ANSI/ISO、USB/Bluetooth、Magic Keyboard、Fn/Globe／Caps Lock LED／IME、sleep/session/撤權、seize gaps、driver stall/kill、背景模式/App kill、長期 latency/CPU/footprint 與每個 Remote Client 的功能矩陣。VirtualHID country US 與 geometry 也需驗收；不支援的 layout 停止翻譯，不代表已驗證所有 physical passthrough 語意。

正式版還需要自己的 Developer ID / notarization 與 root IPC 安全審查。此0.5.15下載是可安裝的候選整合測試包；尚不能承諾移除 Karabiner 後所有 78 規則在你的硬體上都通過。

## 世代、截圖與交接

Helper IPC 升至 version 4：加入 bounded per-device preference／status 與獨立 actionGeneration。physical generation 不隨 remote/device preference 改變；device preference 的晚到動作由 action epoch 拒絕。remote producer 各自有 session／policy gate；metadata job completion 也驗證原 host generation／active epoch。沒有網路握手。

統一 runtime snapshot 與 IPC generation 驗證所有回覆／動作。HID 提供四組 screenshot shortcuts，無第二套截圖 EventTap；所有 App policy 失效立即取消工作。HID → EventTap 先送 stop，收到 physical close／VirtualHID teardown 回覆才解除 ownership gate。3 秒 deadline；只有 stop ACK、從未送出 configure，或 helper process 確定結束（kqueue exit、ESRCH、PID 重用）才算釋放。XPC invalidation／interruption／proxy error 與逾時都鎖定 releaseUnconfirmed，保持新後端停用，直到使用者按「恢復／重啟引擎」；逾時後的晚到 ACK 不會解除。這不是 Driver 實際送達 acknowledgement，需實機測失聯／kill。
