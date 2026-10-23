# Apple 螢幕共享／VNC 快捷鍵：原因、修正與驗收

## 現場觀察（2026-10-23 至 24）

- MacBook 用 macOS「螢幕共享」控制這台 Mac；兩台有 WindowsMacBridge。MacBook 的 Fn／左 Ctrl 交換已在本機啟用，接收端是 1.0.0 build 63。遠端 Mac 的 TextEdit 原生 ⌘C／⌘V 成功，因此同一台 Mac 的剪貼簿可用；這不驗證遠端 Fn 快捷鍵。
- 限定 C 鍵與修飾鍵 metadata 的臨時探針，在接收端看到 `com.apple.screensharing.agent` 送入 Control+C（來源 PID 46853、接收 Codex PID 19509）。Bridge 處理後仍是 Control+C。探針沒有讀取文字或剪貼簿，測完已停止。
- 接收端「遠端校準」起初沒有 Apple agent。將「Windows 模式總開關」關後開，來源開始顯示「已觀察到此來源的輸入」，Fn+C 變得可用。來源設為「原始 Windows 按鍵」但未重啟時，Fn+C／V 失敗；重啟輸入模式後，第一次未成功，後續 Fn+C、Fn+V、Fn+Z 在 TextEdit 實測成功。
- 以上是 1.0.0 build 63 當時的單向觀察；1.0.1 build 64 的反向驗收另記於下方。

## 程式中的問題與原因界線

1. `RemoteAdapterCatalog.discoveryMarkers` 沒有 `ScreensharingAgent.bundle/`。初始／恢復掃描不會主動列出正在執行的 Apple agent，得等未知來源的事件送到 inbox，再非同步查身分。未知來源的第一個快捷鍵依安全設計原樣通過；Ctrl+C 因而可能沒有複製。背景 agent 也未必發出 `NSWorkspace.didLaunchApplicationNotification`。
2. `InputEngine.readConfiguration()` 在 run-loop tick 中使用 `NSLock.try()`，若那一次拿不到鎖便直接返回；`wake()` 又會合併重複喚醒。這存在設定 revision 已更新、但那次喚醒沒有套用且無保證重試的路徑，可使遠端語意／路由維持舊值，直到其他事件或重啟。現場沒有鎖競爭追蹤，**不能斷言**這就是當時每次失敗的唯一原因。
3. 自動語意在 build 63 對 Apple VNC 只翻譯 C／X／V／A；Fn+Z 等 Windows 規則要手動選「原始 Windows 按鍵」。這和「選完 Mac 或 MacBook 就能使用」的期望不符。

## 1.0.1 build 64 的解法

- 用有效簽章、精確的 Apple signing ID 和系統路徑辨識接收端 ScreensharingAgent；在啟動／session 恢復時的既有有界掃描納入此路徑，不由程序名稱猜測任意輸入。身份查詢仍在輸入 callback 外。
- 已辨識的 Apple VNC 來源在「自動」語意下，對原始 Control 快捷鍵套用 Windows 規則，已是 Mac Command 的快捷鍵保持原樣；保留每來源手動選項供特殊客戶端覆寫。MacBook 開關仍只做內建 Fn／Ctrl 交換，不修改外接鍵盤或遠端來源。
- 輸入 run-loop 改為必定讀取短暫鎖住的設定 mailbox，避免合併喚醒時漏掉 revision。session 恢復後，路由啟用時再掃描一次來源。

## 雙向實機驗收與限制

### 1.0.1 build 64 現場結果（2026-10-24）

- 這台 Mac 以 Apple「螢幕共享」控制 MacBook，使用這台 Mac 的外接鍵盤，在 MacBook 的文字編輯實測 Ctrl+C、Ctrl+V、Ctrl+Z 成功。Fn+C／Fn+V 曾失敗，原因是當時給錯測試按鍵；這台 Mac 沒有開啟 MacBook 內建鍵盤的 Fn／Ctrl 交換。
- 這台 Mac 的外接鍵盤經通用控制送到 MacBook，文字編輯 Ctrl+C／Ctrl+V 成功。MacBook 內建鍵盤在本機文字編輯 Fn+C／Fn+V 成功；再經通用控制送到這台 Mac，文字編輯 Fn+C／Fn+V 成功。使用者說明測試文件中的額外字母 `v` 是自己按到的，不能當成首次快捷鍵失效證據。
- 這台 Mac 已核對安裝 1.0.1 build 64；MacBook 的 Bridge 介面此前也顯示 1.0.1 build 64。這些是使用者實體鍵盤回報與這台 Mac 的文字編輯內容觀察；未重新連線測第一下、未移除 Karabiner 後複測，也未驗收所有快捷鍵／App。Karabiner 現存不妨礙上述路徑，不代表它在所有情境都沒有影響。

兩台各自安裝 **相同新版**，各自核准輔助功能與輸入監控；MacBook 開啟內建鍵盤模式，一般 Mac 保持關閉。每個接收端的 Windows 模式保持開啟、遠端語意用「自動」。依 App 內 [TwoMacAcceptance.md](../Resources/TwoMacAcceptance.md) 先後做 MacBook → Mac 和 Mac → MacBook 的 TextEdit Fn／Ctrl+C、V、Z；重新連線後記錄第一下與第二下。純測試／CI、已發佈安裝包、單向成功都不能代替反向實機驗收。

來源是在連線建立後才出現時，仍可能要第一個事件才能非同步辨識；安全上不在 callback 查簽章，也不延遲重播可能已失焦的按鍵。若第一次未生效，放開所有鍵重試；連續失敗時看**接收端**的「遠端校準」是否已觀察到 ScreensharingAgent，再查 Windows 模式、權限、Secure Input 和目前 App 規則。不要把「使用共享剪貼簿」當成同機 Fn／Ctrl 快捷鍵成功的證據，也不要把一次總開關重啟當作永久修復。
