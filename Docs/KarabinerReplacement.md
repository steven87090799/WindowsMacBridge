> 以下記錄 0.3 預覽的歷史狀態。0.4 已接上 capture／IPC／installer；目前狀態與未驗收項目以 [HIDIntegration](HIDIntegration.md) 為準。

# Karabiner 替代工作與 0.3.0-preview 的界線

使用者的 78 條規則全部保留為必要需求。原始設定保存於 `Tests/BridgeCoreTests/Fixtures/windows-like-mac-v2.json`，SHA256 為 `27e366cb7114f45eb3ca555326eb170eda223e50c04b6b7f2db4fc6456c6fe53`。此預覽尚不能完整取代 Karabiner。

## 本次可用的快捷鍵路徑

- #13–41：29 條一般快捷鍵與導覽規則。
- #42–60：19 條瀏覽器規則，由預先編譯的 App 清單選擇。
- #11/#12/#78：左 Option+L 鎖定、左 Option+E 開 Finder、Ctrl+Shift+Esc 開活動監視器。系統動作不在 Remote/VM/Game 執行。Option 條件只接受左側。
- #61–76：Finder 15 個不同輸入與 #63 的有條件移動分支。須在設定開啟 Finder 功能；AX 無法確認檔案列表時不做檔案移動、改名或刪除。Finder 圖示檢視與桌面焦點是否能辨識，仍須實機驗證。
- #1/#2：右 Option+P 開關手動穿透，按住重複不會反覆切換。保留在 Remote 中可使用的原設定行為。Menu Bar 與唯音守護也反映穿透狀態。
- #3：集中增加 Remote bundle regex、executable path fallback、瀏覽器與 IDE 排除清單；使用者明確 override 仍有優先權。
- 唯音／其他中文 IME 可選擇實體快捷鍵模式，要求底層 ASCII layout 為 ABC/U.S.。尚未驗證組字中的行為，預設關閉，不宣稱可判斷 composition。

這些是「所有鍵盤的快捷鍵預覽」，並非原 JSON 的裝置範圍等價。新安裝預設選擇使用者要求的內建鍵盤範圍；由於後端尚不具備該能力，引擎停止翻譯並顯示原因。既有 v0.2 使用者保留原全鍵盤範圍。預覽全鍵盤功能需由設定明確選擇。

## 尚未連接到 macOS 的必要功能

| 規則 | 狀態 | 原因 |
| --- | --- | --- |
| #4 | 未完成 | Event Tap 沒有單一實體鍵盤身分，不能以 keyboardType 代替 VID/PID |
| #5–10 | 核心 ledger 已測試；沒有硬體輸入／輸出接線 | Fn/左 Ctrl、左右 Option/Command 交換需要裝置後端與虛擬 HID |
| #77 | 未完成 | consumer brightness usage 不在現有 Event Tap 的普通 key pipeline |
| Alt+Tab | 未完成 | 原設定透過整鍵 Option/Command 交換產生；不能用孤立 Tab 改 flags 取代完整持有行為 |

`HIDDeviceInventory` 僅列出裝置 metadata，沒有 open/seize 或 input callback。`HIDModifierLedger`、`HIDCaptureGate` 是可測試的後端核心，不是假裝存在的 DriverKit adapter。`BackendCapabilities.eventTap.canReplaceRequestedProfile` 必定為 false。

## Finder 狀態與執行限制

Callback 只把動作放入最多 16 筆 mailbox，工作在 callback 之外執行。請求在 600 ms 後或前景/啟用/恢復 epoch 改變時失效；AX 角色查询在 worker 執行，單次 messaging timeout 30 ms。不讀任何 AX 文字、document value、剪貼簿文字或檔案 URL。

Ctrl+X 在確認檔案列表時送 Cmd+C，最多等待 400 ms，只接受 changeCount 恰好增加一次且包含 fileURL 類型，再建立 5 分鐘有效 intent。文字焦點使用 Cmd+X。Ctrl+V 以目前 Finder PID、changeCount、期限、焦點決定 Cmd+V 或 Cmd+Option+V，送出即消耗 intent。輸出是指定 PID 的完整 down/up，private CGEventSource 與 marker 防止自身再翻譯；不持續持有全域 synthetic modifiers。

這無法原子證明是哪個程序寫入 Clipboard，也無法證明 Finder move 成功。極短時間內另一個程序更新 Clipboard，仍存在不可完全消除的競態。原生 Cmd+C 或其他 App Copy 會透過 changeCount 使舊 intent 失效；切 App、暫停、Secure Input、session gap、timeout recovery 也會使 epoch 失效。目的地衝突由 Finder 自己處理。

## 查閱 Karabiner 原始碼後的後端決策

參考固定 revision `31359e8b882ebe6054470c2846f0c5fbd6d2276f`，而不是依賴會變動的 main。

- [entry.hpp](https://github.com/pqrs-org/Karabiner-Elements/blob/31359e8b882ebe6054470c2846f0c5fbd6d2276f/src/apps/CoreService/include/core_service/daemon/device_grabber_details/entry.hpp)：每個 IOHIDDevice 建立獨立 entry，指定裝置使用 `kIOHIDOptionsTypeSeizeDevice`；虛擬裝置不再抓取。
- [device_grabber.hpp](https://github.com/pqrs-org/Karabiner-Elements/blob/31359e8b882ebe6054470c2846f0c5fbd6d2276f/src/apps/CoreService/include/core_service/daemon/device_grabber.hpp)：先確認虛擬鍵盤 ready 才允許 seize；輸出層掉線須清除 held keys 並釋放裝置。
- [modifier_flag_manager.hpp](https://github.com/pqrs-org/Karabiner-Elements/blob/31359e8b882ebe6054470c2846f0c5fbd6d2276f/src/share/modifier_flag_manager.hpp)：modifier ownership 帶 device ID，移除裝置只清除它自己的持有。
- [獨立 VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)：提供 DriverKit virtual keyboard 與 C++ client；官方服務只接受 root client。可以評估沿用官方已簽署 driver；自行重建/換身分發佈 driver 才需要自己的 Apple DriverKit entitlement 與 provisioning。

建議完整後端：

```text
SwiftUI / 輸入法協調器（登入使用者）
    → 驗證呼叫者身分的 IPC：設定、App context、pause、heartbeat
    → Privileged HID helper（裝置白名單、有限隊列、watchdog）
        IOHIDDevice 按裝置 seize
        → 按装置的 physical state / Fn / consumer normalization
        → profile / first-match rules / output ownership
        → VirtualHIDDevice client → 已簽署 DriverKit 虛擬鍵盤
```

不可讓 UI 傳任意 shell 或無限制 HID stream 給 root helper。限制設定 schema、目標使用者/session、鍵盘範圍與動作。服務掉線/心跳停止時先送空 output reports，釋放每個 seized device；服務重啟必須等待所有實體鍵放開。不能同時讓 Event Tap 與 HID backend 翻譯同一批輸入。

已新增可獨立建置的 [VirtualHID helper 原型](../Tools/HIDBackend/README.md)：固定 SDK 與 checksum、Swift/C/C++ bridge、keyboard/Fn/consumer report 編碼、driver readiness/reset、離線生命週期模型。尚未安裝或接入 App。

後續必要工程：driver 安裝版本協調、身分驗證 IPC、root helper 的簽署及安裝移除、ServiceManagement lifecycle、Secure Input/session 同步、physical usage page 正規化、consumer report、真實雙鍵盤與 Fn/Globe 驗收。這些 adapter/installer **尚未完成**。本次未安裝 daemon/driver，未以 root 取得鍵盤独占，未改動 Karabiner 或系統設定。

## 驗收

自動測試分成原始 fixture 的 66 個不同 shortcut inputs、#63 Finder state、toggle/Remote/scopes、core down/up 與高頻事件、HID ledger 的 6 組映射／雙裝置釋放／轉 Remote，以及平台 AppKit 測試。通過不等於真實 HID 或遠端驗收。

完整替代仍須逐條驗證 78 條，加上原始需求未在 JSON 明列的裸 Home/End、Shift+Home/End。必要環境包含內外接同時按鍵、USB/Bluetooth hotplug、唯音組字、Finder 所有檢視與文字框、Remote 全螢幕、sleep/wake、撤權、Secure Input、helper/driver crash、長時間 CPU/記憶體/延遲測量。
