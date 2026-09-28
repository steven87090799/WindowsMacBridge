# WindowsMacBridge 0.4.1 設定與圖示測試版

macOS 14+、Apple Silicon。唯音／ABC 守護與 Windows 快捷鍵在同一個 Menu Bar App。

這個包已接上 App → 驗證身分的 XPC → 指定裝置擷取 → VirtualHID 輸出管線。**仍是待實機驗收的開發版，不能宣稱已完整取代 Karabiner。** App/helper 是 ad-hoc 簽章、未公證；只有包內原廠 VirtualHID 套件有 Developer ID 與 Apple 公證。請保留 Karabiner 安裝，先停用其相同映射再測試。

## 一般快捷鍵：最快開始

1. 解壓 ZIP、結束舊版，將 `WindowsMacBridge.app` 放進「應用程式」並開啟。
2. 在一般頁要求輔助使用，依 macOS 提示核准目前 App；權限不能由下載包自動套用。
3. 新安裝預設啟用 EventTap／所有鍵盤，Codex 的聊天與文字輸入使用 Default macOS。舊設定會保留，要套用這組設定請按「套用建議預設」。
4. 先在測試文件確認 Ctrl+C／X／V，再測 Codex。新版預設也開啟底層 ABC／U.S. 的中文／唯音快捷鍵；Terminal／Remote／VM／Game 保持穿透，Finder 檔案加強仍需另行開啟。

普通快捷鍵不需執行 Install.command，不需 root helper 或 Driver。每個設定已有說明，完整操作及預設值見包內 `UserGuide.md`，設定頁也可開啟。只有需要 Fn／Control、Option／Command 與亮度鍵映射時，才進行下方進階安裝。

## 進階 HID 安裝（選用）

1. 解壓 ZIP；先從 Menu Bar 結束舊 WindowsMacBridge。完整資料夾保持在一起，不只拖出 App。
2. 執行 `Install.command`，macOS 會要求管理員授權，安裝 App、root helper 與官方 VirtualHID 8.6.0。已有不同共用 Driver 版本時會停止，不會降版。開發版若被 Gatekeeper 阻擋，請使用系統提供的「仍要打開」；安裝器不關閉 Gatekeeper／SIP。
3. 依官方 Manager／macOS 提示核准 Driver；系統要求重啟時先重啟。需要再要求啟用，可執行 `ActivateDriver.command`。
4. App 設定 → 一般與權限：選「指定鍵盤 HID 後端」，要求 App 的輔助使用、helper 的輸入監控。若需手動加入：系統設定 → 隱私權與安全性 → 輸入監控 → `+`，用 ⌘⇧G 選擇 `/Library/Application Support/WindowsMacBridge/BridgeHIDHelper.app`。更新後若權限失效，移除舊授權再加入新版本。
5. 確認 Helper／VirtualHID 顯示 Ready、啟用 Windows 快捷鍵，放開所有按鍵。Finder 功能需另行開啟；中文 IME 設定保留你的選擇，新安裝為開啟。唯音輸入法本體仍需另行安裝。

新安裝預設 EventTap，不擷取實體裝置；既有設定保留。HID 需明確選擇且僅支援指定鍵盤。未 Ready、未授權、裝置描述不支援、Secure Input、失去前景 session 或控制 App 心跳逾時，均停止擷取。沒有適用鍵盤時會顯示原因，不會套用到所有外接鍵盤。

## 本版行為

- 僅內建或 Apple VID 1452 / PID 834 的支援鍵盤服務；排除 virtual／mouse／multitouch、非布林輸入或未知 descriptor，最多 16 個服務。並非所有 HID 硬體皆已確認相容。
- 本機 macOS 模式：Fn ↔ 左 Control、左右 Option ↔ Command；29 組一般規則、19 組瀏覽器規則、Finder／系統動作、亮度增加 consumer 鍵→Enter。Alt+Tab 的 Command 持有會保留至實體 Option 放開。
- Terminal／IDE／Remote／VM／Game／Disabled：整個 HID 按鍵維持原樣。這刻意比原始 Karabiner 的 Terminal 僅排除部分 Ctrl 規則更保守，保護 Unix／遠端語意。本機／Terminal 保留右 Option+P 穿透與 Ctrl+Option+Command+P 緊急暫停。Remote／VM／Game／Disabled 直接釋放實體鍵盤，這些情境請用 Menu Bar 暫停；未在其原生鍵流攔截保留熱鍵。
- 本機切入遠端若正按住按鍵，先釋放舊虛擬輸出並交回實體鍵盤。返回本機時等所有實體鍵放開才再次接管；不把舊的 Command 持有搬進遠端。前景通知與鍵盤仍非原子同步。
- 手動穿透涵蓋 Fn、consumer 與所有本機動作。Menu Bar 暫停／結束會釋放擷取。
- Finder 剪下只記住剪貼簿 changeCount／類型，不讀取內容，移動仍由 Finder 執行；不能確認移動成功。
- 不保存普通打字、剪貼簿、密碼、OTP；不網路上傳鍵盤資料。HID 診斷只顯示計數、最大 callback 處理時間及最近命中規則 ID；不是逐鍵紀錄。

## 停止與移除

先用 Menu Bar 暫停／結束。若 App 無回應，執行 `Stop.command` 停止 helper，解除實體擷取。App 崩潰／心跳斷線的 lease 上限為 1 秒，driver 回應停滯 500 ms 時觸發釋放；實際崩潰與硬體狀態仍待驗收。重啟服務可再執行 Install.command。

`Uninstall.command` 移除本工具的 helper 與兩個 launchd 註冊；保留 App、使用者設定、更新前 App 備份與共用官方 Driver，避免破壞其他軟體。App 若也不需要，可自行移出 /Applications。官方 Driver 的移除請依原廠文件；不要在其他軟體仍使用時移除。

## 安裝後驗收

先在可丟棄文件測 Ctrl+C/X/V/Z/Y、左右 Shift、快速連按、Alt+Tab／Shift+Tab，再測 Terminal Ctrl+C。測 Finder 開啟／改名／剪下與貼上，以及剪下後其他 App Copy。遠端需分別驗證 Windows App、Parsec 或你使用的 Client：Ctrl+C/V、Alt+Tab、Ctrl+Alt+Delete、Clipboard 各自不同，本工具只能保證自己的 profile 選擇，不能保證 Client 傳送策略。

另外測 Fn／Globe 與輸入法切換、亮度增加鍵、Caps Lock 中文切換、中文組字、外接鍵盤不受影響、睡眠／喚醒、拔除／重連、撤權、helper／App 強制結束、按住修飾鍵切入遠端。ANSI／ISO／JIS、Bluetooth、複合 consumer 服務、driver 接管時的 Caps Lock 狀態／LED、端到端延遲與長期 CPU／記憶體均未完成實機驗收。

本版已通過 82 項主程式與 11 項 helper 離線測試；含新安裝預設、舊設定保留、損壞設定安全停用、120,000 次 HID 引擎事件與 100,000 次 report 編碼。離線測試不代表實體接管或長期背景驗收。

官方 SDK / Driver：
https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ba98de7fae2d529b9debe82890765dc66246f4ff
