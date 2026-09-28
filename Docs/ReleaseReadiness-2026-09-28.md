# 0.4.1 正式上線前驗收紀錄（2026-09-28）

狀態：**尚未符合正式發布門檻**。本頁分開記錄目前安裝的
`v0.4.1-preview.2`、尚未安裝的後續修正，以及真實硬體／遠端驗收。
離線測試、權限成功與短期低 CPU 都不能替代實體鍵盤或三小時結果。

## 已完成的驗證

| 項目 | 結果與範圍 |
| --- | --- |
| 主程式與核心 | 85 個測試通過：一般／瀏覽器／Finder 規則、左右修飾鍵、按住鍵切 App、Remote 穿透、暫停、迴圈標記、故障恢復模型、唯音守護及設定遷移。含 120,000 事件壓測；僅程序內事件。 |
| HID helper | 11 個測試通過，含 100,000 次 report 編碼；未連接 Driver 或擷取實體鍵盤。 |
| AddressSanitizer | 鍵盤／HID 核心 32 個測試通過；未發現該路徑的記憶體錯誤。不涵蓋 AppKit／WindowServer 的實際輸入。 |
| 建置 | 主 App 與 helper 的 Release 建置及 `--self-check` 通過；安裝中仍是 preview.2，尚未包含本次修正。 |
| 本機候選包 | `0.4.1-rc.2`（App/helper build 7）ZIP SHA-256 `0038844921b020c984376dc69c977c23f07b8d8a8888a46c713c88b2d66e01d2`；解壓後每筆 payload checksum、App/helper strict codesign 與 self-check 通過。這是未安裝的 ad-hoc 測試包，不是正式發行。 |
| 本機 UI | Accessibility 已授權、Post/Listen 可用、EventTap Active、Secure Input OFF。四個設定分頁可開啟，Codex 規則與 AweSun 自訂 Remote 規則在 UI 中確認，設定視窗關閉後程序仍常駐且只有一份。 |
| 安全輸入 | 原始碼沒有呼叫 `EnableSecureEventInput()` 或 `DisableSecureEventInput()`；只檢查系統安全輸入並停止翻譯。真實密碼欄與切換時序尚未實測。 |
| 裝置與其他常駐程式 | 本機有 AweSun、Parsec、Parallels；AweSun 原先漏列 Remote，已補入下一版清單。本機 VChewingGuard 仍在執行，整合 App 的 Guard 預設關閉，未嘗試同時接管輸入法。 |

## 本次找到並修正、待發布的問題

1. AweSun `com.aweray.awesun.macclient` 原先會落入一般 macOS Profile，可能在遠端桌面誤翻譯。已加入 Remote registry 與回歸測試；目前安裝的 preview.2 已另用 UI 指定 Remote Windows 穿透。
2. HID 的快捷鍵先放開 Ctrl／Shift、字母仍按住時，輸出可能變成不帶修飾鍵的字母；跨兩把鍵盤的最後一個 Ctrl 放開亦然。新增先失敗再通過的測試，現在永久結束該按鍵輸出，重新按下修飾鍵不復活。拔掉持有修飾鍵的鍵盤也採同一規則。
3. HID 未選用時原本仍建立每 250 ms 的心跳計時器。現在只在 HID 啟用且協調器已啟動時排程；停用即取消。
4. EventTap 閒置時原本每 250 ms 重建空的診斷陣列；五分鐘診斷到期後還會反覆清空。現在只在記錄變化時整理，到期只清一次。

## 三小時觀察

安裝的 preview.2 從 **2026-09-28 06:07:12 UTC** 開始，以 launchd
啟動的一次性程序，每 60 秒取一次 App PID、累積 CPU 秒、RSS；每五次取
一次 `vmmap` physical footprint。預定到 **09:07:12 UTC** 自行停止。資料在
`~/Library/Caches/WindowsMacBridge/Monitoring/three-hour-20260928-0608Z.csv`。
監控不讀取按鍵、剪貼簿、視窗標題或文件。應按相同 PID 的 CPU 秒差計算
單核心平均 CPU；以樣本間隔辨識睡眠或空窗。設定視窗開啟時會增加記憶體，
必須與關窗閒置分開解釋。此時段尚未結束，不得宣稱三小時通過。監控的是
修正前的已安裝版；不能直接當作修正版資源數據。

## 正式發布阻礙與驗收矩陣

| 優先級 | 檢查項目 | 目前狀態／門檻 |
| --- | --- | --- |
| P0 | 正式簽章、公證與 Gatekeeper | App 與 helper 目前為 ad-hoc 簽章；`spctl --assess` 對安裝版回報 rejected。正式下載安裝需要自己的 Developer ID、notarization、stapling 與乾淨機器驗收。 |
| P0 | 目前實體鍵盤與既有映射 | `defaults -currentHost read -g` 留有 Logitech VID 1133、PID 45929／45938 的 Control／Command 對調偏好；需先確認哪把鍵盤仍使用該設定，再用原設定與暫時預設鍵位做對照。勿在未做對照前聲稱 Ctrl 快捷鍵來自本程式，亦不能擅自改掉使用者鍵位。 |
| P0 | 本機快捷鍵端到端 | Codex 聊天、TextEdit、Safari、Finder 的實體 Ctrl+C/X/V/A/Z/Y/S/F/P、Alt+Tab、按住與快速連打仍未用實體按鍵驗收。UI 自動化送鍵沒有進 EventTap 計數，不算通過。 |
| P0 | Terminal、IDE、IME、安全輸入 | 真實 shell 控制鍵、Codex 內建終端機、唯音組字與候選、Caps Lock、密碼欄切換仍未實測。Codex 預設 macOS 規則僅適合聊天／文字輸入。 |
| P0 | 遠端與 VM | AweSun、Parsec、Parallels 均有保護規則，但尚未在真實 Session 驗證 Ctrl+C/V、Alt+Tab、全螢幕、剪貼簿與 Client 自己的映射。Chrome Remote Desktop 等瀏覽器分頁無法由 bundle ID 自動辨識。 |
| P0 | HID 真實擷取 | Root helper／Driver 未安裝，未驗證 USB、Bluetooth、Magic Keyboard、Fn／Globe、ANSI／ISO、兩把鍵盤、快速拔插及 crash 後輸出釋放；不能宣稱取代 Karabiner。 |
| P1 | 跨 App 與恢復 | Ctrl 按住切換 App／Remote、sleep／wake、Fast User Switching、登出重登入、權限撤銷、tap timeout、App 強制結束需要實機逐項記錄。模型測試已通過。 |
| P1 | Finder 剪下 | 增強預設關閉；只測過 metadata 狀態機，尚未在測試檔案上驗證複製、變更剪貼簿、跨視窗與實際移動結果。 |
| P1 | 長期資源 | 三小時採樣進行中；正式版仍需 24 小時閒置＋打字／切換負載 soak、p50/p99 callback 與 energy impact。現有 UI 只提供 callback 最大值。 |
| P2 | 鍵盤配置與額外 App | Dvorak、非美式配置、Electron／Java／Wine／遊戲、外接裝置專屬映射、更多 Remote Client 需要擴充矩陣。未知配置目前原樣通過。 |

每個遠端 Client 驗收都應記錄 macOS 與 Client 版本、視窗／全螢幕、
本機鍵盤配置、Client 自身鍵位設定，以及 Bridge 關閉／啟用的對照。
「穿透」只表示本程式不改鍵，不保證 Client 能傳送 Alt+Tab、Ctrl+Alt+Delete
或同步剪貼簿。不得在日常資料或敏感文件上做故障注入。
