# 0.4.1 正式上線前驗收紀錄（2026-09-28）

狀態：**尚未符合正式發布門檻**。本頁分開記錄目前安裝的
`v0.4.1-preview.2`、尚未安裝的後續修正，以及真實硬體／遠端驗收。
離線測試、權限成功與三小時閒置低 CPU 都不能替代實體鍵盤或遠端驗收。

## 已完成的驗證

| 項目 | 結果與範圍 |
| --- | --- |
| 主程式與核心 | 86 個測試通過：一般／瀏覽器／Finder 規則、左右修飾鍵、按住鍵切 App、Remote 穿透、暫停、迴圈標記、故障恢復模型、唯音守護及設定遷移。含 120,000 事件壓測及固定種子的 100,000 步雙鍵盤交錯／切換／拔插／重啟測試；僅程序內事件。 |
| HID helper | 11 個測試通過，含 100,000 次 report 編碼；未連接 Driver 或擷取實體鍵盤。 |
| AddressSanitizer | 鍵盤／HID 核心 33 個測試通過，包含雙鍵盤交錯壓測；未發現該路徑的記憶體錯誤。不涵蓋 AppKit／WindowServer 的實際輸入。 |
| 建置 | 主 App 與 helper 的 Release 建置及 `--self-check` 通過；安裝中仍是 preview.2，尚未包含本次修正。 |
| 本機候選包 | `0.4.1-rc.2`（App/helper build 7）ZIP SHA-256 `0038844921b020c984376dc69c977c23f07b8d8a8888a46c713c88b2d66e01d2`；解壓後每筆 payload checksum、App/helper strict codesign 與 self-check 通過。這是未安裝的 ad-hoc 測試包，不是正式發行。 |
| 本機 UI | Accessibility 已授權、Post/Listen 可用、EventTap Active、Secure Input OFF。四個設定分頁可開啟，Codex 規則與 AweSun 自訂 Remote 規則在 UI 中確認。五分鐘暫停顯示「已暫停」，手動恢復後 EventTap 仍為 Active；設定視窗關閉後程序仍常駐且只有一份。這仍不驗證實體快捷鍵。 |
| 安全輸入 | 原始碼沒有呼叫 `EnableSecureEventInput()` 或 `DisableSecureEventInput()`；只檢查系統安全輸入並停止翻譯。真實密碼欄與切換時序尚未實測。 |
| 裝置與其他常駐程式 | 本機有 AweSun、Parsec、Parallels；AweSun 原先漏列 Remote，已補入下一版清單。本機 VChewingGuard 仍在執行，整合 App 的 Guard 預設關閉，未嘗試同時接管輸入法。 |

## 本次找到並修正、待發布的問題

1. AweSun `com.aweray.awesun.macclient` 原先會落入一般 macOS Profile，可能在遠端桌面誤翻譯。已加入 Remote registry 與回歸測試；目前安裝的 preview.2 已另用 UI 指定 Remote Windows 穿透。
2. HID 的快捷鍵先放開 Ctrl／Shift、字母仍按住時，輸出可能變成不帶修飾鍵的字母；跨兩把鍵盤的最後一個 Ctrl 放開亦然。新增先失敗再通過的測試，現在永久結束該按鍵輸出，重新按下修飾鍵不復活。拔掉持有修飾鍵的鍵盤也採同一規則。
3. HID 未選用時原本仍建立每 250 ms 的心跳計時器。現在只在 HID 啟用且協調器已啟動時排程；停用即取消。
4. EventTap 閒置時原本每 250 ms 重建空的診斷陣列；五分鐘診斷到期後還會反覆清空。現在只在記錄變化時整理，到期只清一次。

## 三小時觀察：已完成

觀察的是已安裝的 **v0.4.1-preview.2，build 6**，不是尚未安裝的 build 7。
時段為 **2026-09-28 06:07:12–09:07:12 UTC**（台灣 **14:07:12–17:07:12**）。
一次性 launchd 程序每 60 秒取 App PID、累積 CPU 秒與 RSS；每五分鐘取一次
`vmmap` physical footprint。CSV 包含 181 筆資源樣本與 37 筆 footprint 樣本。
全程同一 PID，181 筆皆 running，最長採樣間隔 60 秒，沒有缺失 CPU／RSS 欄位；
監控程序自行結束，exit code 0，stdout／stderr 均為空。

| 資源 | 開始 | 結束 | 本次樣本最大值 |
| --- | --- | --- | --- |
| RSS | 82.98 MiB | 64.55 MiB | 123.25 MiB（設定視窗操作時） |
| Physical footprint | 54.1 MiB | 64.1 MiB | 67.9 MiB（五分鐘採樣） |
| CPU time | 3.04 秒 | 18.01 秒 | 增量 14.97 秒 |

**平均單核心 CPU = 14.97 / 10800.2 × 100 = 0.13861%。**
一分鐘 CPU 平均的中位數為 0.10%，最高為 1.97%（設定視窗操作時），
這個最高值不是瞬間峰值。第二、三小時平均約 0.10%／0.11%。
Footprint 在操作設定後升至 67.9 MiB，後續維持約 64–65 MiB；
本時段沒有持續增長的趨勢，仍不能據此證明不存在記憶體洩漏。
監控結束後 `vmmap` 顯示程序生命週期 footprint peak 73.3 MiB；
該值沒有發生時間，不能直接當成本次三小時的峰值。MiB 使用 1024² bytes。

監控前段執行過設定分頁、Profile 與暫停／手動恢復檢查；其餘主要為背景閒置。
結案時 App 仍為同一 PID、EventTap Active、Secure Input OFF，診斷關閉。
UI 顯示生命週期累積 **24 個處理事件／0 個翻譯事件**、最大 callback **100.21 µs**；
因此不能把此結果描述為密集打字、快捷鍵端到端或遠端負載測試。
沒有刻意讓 Mac 睡眠、登出、撤銷權限或讓輸入程序崩潰。
系統電源日誌在此時段未列出 Sleep／Wake，資源採樣亦未見空窗；
未找到 WindowsMacBridge／BridgeHIDHelper 崩潰報告。

日誌並非完全無錯誤。限定 WindowsMacBridge 程序的系統 error／fault 查詢找到：

- 192 筆 CoreUI bundle 查找失敗。
- 96 筆 AppKit geometry 警告（48 筆 negative width、48 筆 negative height）。
- 3 筆 Apple framework 的 scene／XPC 連線錯誤。

前兩類集中在 **14:16–14:31** 的設定視窗操作，後續關窗閒置未再出現；
不應直接推斷為 EventTap 失效，也不能宣稱根因已解決。列為 P1 UI／macOS 27 相容性問題，
下一步需在受控 UI harness 中重現並確認 bundle／layout 根因，再比較 macOS 14／15。
剩餘三筆不足以判定是系統暫時中斷或本程式錯誤，保留為未解明事件。

監控只保存資源資料，不讀取按鍵、剪貼簿、視窗標題或文件；原始 CSV 留在本機
`~/Library/Caches/WindowsMacBridge/Monitoring/three-hour-20260928-0608Z.csv`，不加入 Git。
結案時已 `launchctl bootout` 移除一次性工作 `local.WindowsMacBridge.ResourceMonitor.20260928`，
並刪除本次 heartbeat 追蹤；未替換 App、切換輸入法或更動輸入設定。

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
| P1 | 設定視窗／macOS 27 相容性 | 操作視窗時重複 CoreUI bundle 與 AppKit 負尺寸警告，根因未解。需要隔離重現與修正，不能把關窗後安靜當作修復。 |
| P1 | 長期資源 | preview.2 三小時主要閒置採樣完整、平均單核心 CPU 0.14%，未見持續記憶體增長；正式版仍需修正版重測及 24 小時閒置＋打字／切換負載 soak、p50/p99 callback 與 energy impact。現有 UI 只提供 callback 最大值。 |
| P2 | 鍵盤配置與額外 App | Dvorak、非美式配置、Electron／Java／Wine／遊戲、外接裝置專屬映射、更多 Remote Client 需要擴充矩陣。未知配置目前原樣通過。 |

每個遠端 Client 驗收都應記錄 macOS 與 Client 版本、視窗／全螢幕、
本機鍵盤配置、Client 自身鍵位設定，以及 Bridge 關閉／啟用的對照。
「穿透」只表示本程式不改鍵，不保證 Client 能傳送 Alt+Tab、Ctrl+Alt+Delete
或同步剪貼簿。不得在日常資料或敏感文件上做故障注入。
