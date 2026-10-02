# WindowsMacBridge 0.5.17（build 30）統一輸入候選版

macOS 14+、Apple Silicon。唯音／ABC 守護與 Windows 快捷鍵在同一個 Menu Bar App。

這個包已接上 App → 驗證身分的 XPC → 指定裝置擷取 → VirtualHID 輸出管線。**仍是待實機驗收的開發版，不能宣稱已完整取代 Karabiner。** App/helper 是 ad-hoc 簽章、未公證；只有包內原廠 VirtualHID 套件有 Developer ID 與 Apple 公證。請保留 Karabiner 安裝，先停用其相同映射再測試。

## 一般快捷鍵：最快開始

1. 解壓 ZIP、結束舊版，將 `WindowsMacBridge.app` 放進「應用程式」並開啟。
2. 在一般頁要求輔助使用，依 macOS 提示核准目前 App；權限不能由下載包自動套用。
3. 新安裝預設啟用裝置 HID／所有支援鍵盤，需要完成下方 helper／Driver 安裝；Codex 的聊天與文字輸入使用 Default macOS。舊版 EventTap 選擇保留；不會自動安裝 Driver。
4. 先在測試文件確認 Ctrl+C／X／V，再測 Codex。新版預設也開啟底層 ABC／U.S. 的中文／唯音快捷鍵；Terminal／Remote／VM／Game 保持穿透，Finder 檔案加強仍需另行開啟。

使用 EventTap 備援不需要 root helper／Driver；逐裝置偏好及通用控制來源分流需要 HID。Fn／Globe 預設保留，Control+C 用真正的 Control。HID 接收端不再要求切換 Sender／Receiver；Remote 是逐來源設定，不能停掉本機鍵盤。

## 進階 HID 安裝（選用）

1. 解壓 ZIP；先從 Menu Bar 結束舊 WindowsMacBridge。完整資料夾保持在一起，不只拖出 App。
2. 執行 `Install.command`，macOS 會要求管理員授權，安裝 App、root helper 與官方 VirtualHID 8.6.0。官方 8.0.0–8.6.0 若 ABI、簽章、receipt 與 binary 版本皆符合，就沿用且不改寫共用 Driver、不重啟既有共用 daemon。已核對 7.3.0 的升級先保存 App/helper/Driver/receipt/服務狀態，失敗回復；仍有其他共用 client 或未知版本則停止。需要重新開機／未完成回復會保留 protected recovery，不能視為安裝完成；下次執行 Install.command 先復原。任意 DriverKit ABI 升級及真實 OS activation/rollback 仍待驗收。開發版若被 Gatekeeper 阻擋，請使用系統提供的「仍要打開」；安裝器不關閉 Gatekeeper／SIP。
3. 依官方 Manager／macOS 提示核准 Driver；系統要求重啟時先重啟。需要再要求啟用，可執行 `ActivateDriver.command`。
4. App 設定 → 一般與權限：選「指定鍵盤 HID 後端」，按 App 的「要求／修復授權」，完成同一個鍵盤控制系統開關；helper 的輸入監控仍獨立。若需手動加入：系統設定 → 隱私權與安全性 → 輸入監控 → `+`，用 ⌘⇧G 選擇 `/Library/Application Support/WindowsMacBridge/BridgeHIDHelper.app`。更新後若權限失效，移除舊授權再加入新版本。
5. 確認 Helper／VirtualHID 顯示 Ready、啟用 Windows 快捷鍵，放開所有按鍵。Finder 功能需另行開啟；中文 IME 設定保留你的選擇，新安裝為開啟。唯音輸入法本體仍需另行安裝。

新安裝預設 HID，既有 backend 選擇保留。符合所選範圍與安全 descriptor 且沒有 Native Mac 裝置覆寫才擷取。未 Ready、未授權、描述不支援、Secure Input、失去前景 session 或控制 App 心跳逾時，均停止擷取。沒有適用鍵盤時顯示原因。

## 本版行為

- 可選所有支援的簡單 keyboard descriptor，或內建／Apple VID 1452 / PID 834；可完整轉送標準 keyboard＋相對 mouse composite；排除 virtual／multitouch、絕對座標與未知 descriptor，最多 16 個服務。並非所有 HID 硬體皆已確認相容。
- 所有鍵盤皆為 Windows Experience 時，HID 保留原始 Ctrl 等 App-sensitive 輸入；接收端只有在 annotated recipient 等於本機前景 App 時才選規則。來源 helper 不能執行 Finder／AX／Clipboard action。來源 Terminal → 接收文字 App 的 Ctrl+C 由接收 App 決定；兩台 Mac 均需新版 App/helper，實際 UC 尚待驗收。
- Win+L/R/Tab 的純 HID 系統輸出依開關編碼，隨實體／UC 路徑傳送，避免原始 Win+Tab 被 WindowServer 當作 Cmd+Tab。新安裝 Win+R/Tab 仍預設關閉。接收端需要 native session routing 的原生 Cmd+Tab 等使用窄範圍輸出、自有 marker 與 private source，不做自製 MRU／視窗切換器。
- Remote／VM／Game／Disabled 交回原生鍵盤 ownership。Terminal 保留原始 Ctrl；IDE 等保護由接收端 context 判斷。Fn／Ctrl 交換僅由一個 backend 持有，source layout／普通 App 切換不應使 raw Ctrl 遺失。
- Finder 亮度鍵 Enter 暫停支援，亮度鍵保持原生用途。混合 Native Mac 裝置或指定鍵盤範圍無法取得跨機裝置來源證據，Finder／AX／HID 截圖增強保持停用並顯示限制。
- 本機切入遠端若正按住按鍵，先釋放舊虛擬輸出並交回實體鍵盤。返回本機時等所有實體鍵放開才再次接管；不把舊的 Command 持有搬進遠端。前景通知與鍵盤仍非原子同步。
- 手動穿透涵蓋 Fn、consumer 與所有本機動作。Menu Bar 暫停／結束會釋放擷取。
- Finder 剪下只記住剪貼簿 changeCount／類型，不讀取內容，移動仍由 Finder 執行；不能確認移動成功。
- 不保存普通打字、剪貼簿、密碼、OTP；不網路上傳鍵盤資料。HID 診斷只顯示計數、最大 callback 處理時間及最近命中規則 ID；不是逐鍵紀錄。

## 停止與移除

先用 Menu Bar 暫停／結束。若 App 無回應，執行 `Stop.command` 停止 helper，解除實體擷取。App 崩潰／心跳斷線的 lease 上限為 1 秒，driver 回應停滯 500 ms 時觸發釋放；實際崩潰與硬體狀態仍待驗收。重啟服務可再執行 Install.command。

`Uninstall.command` 停止並移除本工具的 helper 與其 launchd 註冊；保留 App、使用者設定、更新前 App 備份，以及共用官方 Driver、VirtualHID daemon 和其 launchd 註冊。即使 daemon 最初由 Bridge 安裝，也可能已有其他軟體連線，因此移除 Bridge 不會停止它。App 若也不需要，可自行移出 /Applications。共用服務會繼續執行；確認其他軟體都不再需要後，才依原廠文件另外移除 Driver 與服務。

## 安裝後驗收

先在可丟棄文件測 Ctrl+C/X/V/Z/Y、左右 Shift、快速連按、Alt+Tab／Shift+Tab，再測 Terminal Ctrl+C。測 Finder 開啟／改名／剪下與貼上，以及剪下後其他 App Copy。遠端需分別驗證 Windows App、Parsec 或你使用的 Client：Ctrl+C/V、Alt+Tab、Ctrl+Alt+Delete、Clipboard 各自不同，本工具只能保證自己的 profile 選擇，不能保證 Client 傳送策略。

另外測 Fn／Globe 與輸入法切換、亮度增加鍵、Caps Lock 中文切換、中文組字、外接鍵盤不受影響、睡眠／喚醒、拔除／重連、撤權、helper／App 強制結束、按住修飾鍵切入遠端。ANSI／ISO／JIS、Bluetooth、複合 consumer 服務、driver 接管時的 Caps Lock 狀態／LED、端到端延遲與長期 CPU／記憶體均未完成實機驗收。

本版架構、完整測試與來源支援等級列在原始碼 Docs/ConsistencyRepair-2026-10-02.md。Google host 有獨立 PID／簽章 adapter，其餘軟體依觀察到的 producer 做保守處理／單次校準；尚無遠端列為 Verified。離線測試不代表六個跨機情境或長期背景驗收。

官方 SDK / Driver：
https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ba98de7fae2d529b9debe82890765dc66246f4ff

## 更新失敗與復原

Install.command 要求先結束 App。安裝器以私人 root staging 驗證 checksum、簽章、App/helper 相同版本與 controller pin，再切換。一般錯誤會還原原本 App/helper/pin/launchd 狀態，最多保留兩份可識別的 App 備份；若還原失敗會保留 recovery snapshot 並顯示位置。缺少 Driver receipt 屬正常首次安裝；查詢錯誤仍返回失敗。已驗證相容的 8.0.0–8.6.0 沿用；未知 ABI 不自動升降版。SIGKILL／斷電後保留受保護的 recovery journal；再次執行 Install.command 會先還原舊 App/helper/pin/服務。App 偵測到未完成交易會停用輸入與相關工作，完成復原後重開。原交易 PID 仍存活時拒絕接管；PID 重用的歧義採保守拒絕。共用官方 Driver 安裝副作用與 DriverKit activation 仍需管理員實機驗收。
