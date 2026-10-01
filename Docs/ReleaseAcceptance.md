> 這份文件保留歷史版本記錄；目前行為、測試與阻擋項目以 [2026-09-30 修復報告](PreReleaseRepair-2026-09-30.md) 為準。自製 Alt+Tab 已移除，不再列為待實作功能。

> 此頁保留 0.2 驗收歷史。0.3 新增項目與仍未完成的 HID 替代要求見 [KarabinerReplacement.md](KarabinerReplacement.md)。中文 IME 與 Finder 功能現為可選預覽；未宣稱實機通過。

# 開發預覽驗收

## 已自動化的範圍

Core 規則與 down/up、repeat、左右 Ctrl、modifier 不一致、釋放 Ctrl 後不復活 Command、Remote 轉換、pause 配對、injection marker、恢復熔斷、120,000 事件平衡。Platform registry 與 flags 保留。

另以人工建立的 CGEvent 經正式 EventRewriter 轉成 NSEvent，再呼叫程序內 NSMenu.performKeyEquivalent，確認 9 組快捷鍵（包含 Ctrl+Y → Cmd+Shift+Z）均命中正確 action。沒有全域注入，也不讀寫 Clipboard。這不是實際硬體／WindowServer event tap 的端到端驗收。

## 必須實機完成，尚未宣稱通過

1. 固定 `.app` 路徑，初次未授權 CPU、授權／撤權、啟用與停用。
2. ABC／U.S.：TextEdit、Safari、Finder Copy/Paste；原生 Command 與 Ctrl-click。
3. Ctrl+Y 在 NSTextView、WebKit、Electron 的 Redo；若不成立，停用該 App rule，不能任意增加注入。
4. Terminal/iTerm/Ghostty Ctrl+C/D/Z/R/L/W/U/K/A/E；IDE integrated terminal 全程通行。
5. 左右 Ctrl/Shift 同時按下、Ctrl 提早放開、repeat、快速交錯、啟動時 modifier 已按住。
6. Ctrl 按住切換 App、Remote 全螢幕、Remote 回本機、至少兩台鍵盤、Bluetooth 斷線。
7. 中文輸入法、Caps Lock 切換、ANSI/ISO、非 US 配置必須原樣通過。
8. Secure Input、sleep/wake、Fast User Switching、logout/login。
9. Event tap timeout／disabled user input：有界恢復，反覆失敗進 Faulted，Menu Bar 仍可 Quit。
10. Test account 中 crash／kill：本版沒有持續合成 modifier，但仍需確認目標 App 對事件改寫的反應。
11. Instruments：暖機後 24 小時 idle/typing/activation soak；記錄 CPU、RSS 與 callback p50/p99/p99.9/max。目前只有 max 診斷，未實作 histogram。

不要以單元測試的人工事件直接灌入日常工作環境。系統層負載測試使用測試帳號、無敏感資料的 TestHost。

## Remote matrix：所有 Client 尚未實機驗收

| Client | Ctrl+C/V baseline vs enabled | Alt+Tab capture | Ctrl+Alt+Delete client action | Clipboard sync |
| --- | --- | --- | --- | --- |
| Windows App | Not tested | Not tested | Not tested | Not tested |
| Jump Desktop | Not tested | Not tested | Not tested | Not tested |
| Parsec | Not tested | Not tested | Not tested | Not tested |
| AnyDesk | Not tested | Not tested | Not tested | Not tested |
| RustDesk | Not tested | Not tested | Not tested | Not tested |
| VMware Fusion | Not tested | Not tested | Not tested | Not tested |
| Parallels | Not tested | Not tested | Not tested | Not tested |
| UTM | Not tested | Not tested | Not tested | Not tested |

記錄 macOS build、Client/Guest 版本、keyboard/layout、fullscreen/windowed、capture/mapping 設定、Bridge off/on 與遠端實際觀察結果。

## 下一階段

1. AppKit/WebKit TestHost，真實 down/up 与 flags-only 改寫驗證。
2. Layout-aware shortcut compilation 與中英文 IME 測試。
3. 自製 Alt+Tab 已移除；保留原生 Command+Tab，不重新啟用舊切換器。
4. Finder move intent、非 callback clipboard metadata、明確確認及 TOCTOU 限制。
5. 已驗證的 helper/process registry 與 Remote matrix。


## 0.2.0 整合版追加手動驗收

- 僅一個 Menu Bar／設定視窗／WindowsMacBridge process；重複 open 不產生第二份。
- 首次設定三項功能皆關閉；未授權時單獨使用唯音功能不要求 Accessibility。
- 唯音與 ABC 手動切換、hotkey 四種 preset、衝突時保留原設定、守護 debounce 和有界重試。
- 舊版守護執行中：顯示衝突、hotkey 未註冊、無 TIS 修正；正常結束舊版後可啟用新守護。
- 遠端／VM／Game 前景：guard 選擇工作取消，切換鍵解除註冊；返回本機後依使用者設定恢復。
- 手動與自動來源切換前，Windows 翻譯 gate 關閉；按住 Ctrl 切回 ABC 必須先放鍵才恢復翻譯。
- 使用 Menu Bar 全域 Pause／Resume，確認兩個功能一同停止／恢復，使用者各自 enabled 偏好不變。
- Secure Input 等待中進入 Remote 或 Pause，不在新 App 執行舊的延遲選擇。
- screens sleep、system sleep、inactive session 交錯通知，不因單一 wake 提早恢復。
- 舊版偏好匯入不帶入啟用狀態、登入項目、歷史；新 App 登入啟動需固定安裝路徑。
- 首次、切換、resume 的 IME 組字和不同 App 行為需實機確認；中文 Windows 翻譯仍未啟用。
