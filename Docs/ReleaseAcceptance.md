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
3. Alt+Tab 的 output ownership、滑鼠互動、中止及 crash 測試，通過前不啟用。
4. Finder move intent、非 callback clipboard metadata、明確確認及 TOCTOU 限制。
5. 已驗證的 helper/process registry 與 Remote matrix。
