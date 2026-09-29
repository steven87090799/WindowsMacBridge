# WindowsMacBridge

Windows 快捷鍵相容層與唯音／ABC 輸入法輔助，整合成一個 macOS Menu Bar App。**0.4.3 拖曳安裝個人測試版。** macOS 14+、Apple Silicon；預設 CGEventTap 快捷鍵，進階 HID 後端仍待裝置驗收。

主專案是這個 repository；`vchewing-input-helper` 已移入 `InputSourceCore` 與 `InputSourceSupport`，不需同時執行兩個 App。[整合與遷移](Docs/ProjectIntegration.md)。

## 0.4.3 快速開始

新安裝預設啟用 Windows 快捷鍵、EventTap／所有鍵盤、底層 ABC／U.S. 的中文／唯音快捷鍵、截圖自動複製，以及 Codex 的聊天／文字 Profile。Terminal、其他 IDE、Remote、VM、Game 保留原按鍵；Finder 加強、唯音守護及切換快捷鍵預設關閉。截圖功能會註冊登入啟動，仍可能需要 macOS 核准。更新保留已存設定，可從一般頁按「套用建議預設」。

## 截圖自動複製

「一般與權限 → 截圖」的開關預設開啟；舊設定沒有此欄位時也視為開啟，使用者明確關閉的選擇會持久保存，套用建議預設也不會重設。開啟後，`⇧⌘4` 仍進入 macOS 的互動框選（可按空白鍵切換視窗、Esc 取消）；完成時圖片存到系統截圖指定的資料夾，並以圖片寫入剪貼簿，可立即按 `⌘V`。會盡量沿用 macOS 截圖的儲存位置與格式；不支援的格式採 PNG，指定資料夾不可寫時改存桌面。關閉開關會移除專屬 Event Tap，`⇧⌘4` 由 macOS 原樣處理，不改系統快捷鍵設定，也不使用 Automator。

此功能使用 `/usr/sbin/screencapture` 啟動原生互動截圖。開啟時會立即檢查可執行檔、儲存位置、輔助使用權限及攔截狀態；往後每 30 天用一次性計時器檢查，遇到 tap 停用、session 恢復或權限恢復也會嘗試修復。診斷寫入 `~/Library/Logs/WindowsMacBridge/Screenshot.log`，只記錄狀態、錯誤及儲存路徑，不記錄圖片內容或普通按鍵。Esc 取消不動剪貼簿；若儲存成功但複製失敗，圖片仍留在磁碟，設定頁會顯示錯誤。

為了重新登入與開機後繼續生效，開啟時會註冊 App 的 macOS 登入項目；若 macOS 顯示待核准，需到系統設定核准。關閉時只移除由此功能新增的登入註冊，原本手動開啟的登入項目保留。App 必須持續執行且已獲得所需權限；更新後若 macOS 要求重新授權，需再次核准。離線單元測試無法驗證實機截圖 UI、螢幕錄製權限提示、實際儲存與貼上。

App 改用黑色鍵盤／雙向箭頭圖示，Menu Bar 不再顯示文字；暫停以雙直線表示。所有設定提供可見說明，另附 [完整操作說明](Resources/UserGuide.md)。設定視窗關閉會釋放 SwiftUI 內容，狀態沒變時不重新發布快照。

「診斷 → 版本與編譯資訊」及 Menu Bar 顯示版本與 Build；診斷頁另顯示 UTC 編譯時間、完整 Git commit、原始碼狀態與 Bundle ID，可複製以便回報。`WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --version` 也輸出相同資訊。這些欄位在建置時寫入已簽章 App 的 Info.plist；發行包應由乾淨的 Git commit 建置，確認狀態為 `clean` 且 commit 對應發行 tag。

開啟 DMG，將 App 拖進 Applications，再開啟並授予輔助使用，即可測一般快捷鍵；**一般 EventTap 使用不需 Install.command 或 Driver**。無付費簽章／公證的下載版可能須在系統設定「仍要打開」；更新也可能要重新授權，不能宣稱完全免系統核准。Codex 預設針對不用內建終端機的用法；若要使用終端機，改回 IDE 或移除該規則。

## 進階 HID 整合測試

App 已接上驗證身分的 XPC、指定 IOHIDDevice 擷取與官方 VirtualHID 輸出。下載包包含 App、helper、官方已公證的 Driver 套件、安裝／停止／移除工具。App/helper 仍是未公證的 ad-hoc 開發版，尚待實體鍵盤與遠端驗收，不能宣稱完整替代完成。

- 29 組一般規則、19 組瀏覽器規則、Finder 剪下／移動與系統動作。
- HID 後端只抓取支援的內建或 Apple 1452/834 服務；Fn／左 Control、左右 Option／Command 交換、完整持有的 Alt+Tab、consumer 亮度增加→Enter。
- Terminal／IDE／Remote／VM／Game／Disabled 的 HID 事件原樣通過；保留右 Option+P 與緊急暫停。不同 descriptor、Caps Lock／Globe／IME、Remote Client 仍需逐項驗收。
- 與唯音／ABC 輸入法守護整合；CGEventTap 預覽後端可另選，兩個後端不會同時翻譯。

安裝與實機檢查：[READ-ME-FIRST](Resources/Installer/READ-ME-FIRST.md)。接線、授權與驗收邊界：[HIDIntegration](Docs/HIDIntegration.md)。原始 78 規則與 upstream 研究：[KarabinerReplacement](Docs/KarabinerReplacement.md)。下載／建置不會啟動引擎；HID 需使用者另行安裝及選擇，不能宣稱完整取代 Karabiner。

## 建置與執行

需要 Swift 6 工具鏈（Xcode 或 Command Line Tools）。主程式沒有第三方 Swift 套件；HID helper 使用固定 revision 的官方 C++ VirtualHID SDK。

```sh
bash scripts/test.sh
bash scripts/build-app.sh
bash scripts/package-app-dmg.sh
# 以下僅建置選用的進階 HID 整合包：
bash scripts/build-hid-helper.sh
bash scripts/package-hid-release.sh
open "$(cat build/APP_PATH.txt)"
```

腳本使用 `~/Library/Caches/WindowsMacBridge/` 作建置暫存，避免同步資料夾 FinderInfo 屬性破壞簽章。App 路徑寫入 `build/APP_PATH.txt`；可用 `BRIDGE_BUILD_DIR` 覆寫。Xcode 可直接開啟 `Package.swift`，目前沒有獨立 `.xcodeproj`。

僅診斷，不攔截鍵盤：

```sh
"$(cat build/APP_PATH.txt)/Contents/MacOS/WindowsMacBridge" --self-check
"$(cat build/APP_PATH.txt)/Contents/MacOS/WindowsMacBridge" --diagnose-backend
```

Windows 快捷鍵預設啟用；唯音守護、輸入法切換鍵預設停用。唯音功能使用 TIS 與 Carbon，不需要 Accessibility，且需先安裝唯音。若 VChewingGuard 還在執行，輸入法頁會顯示衝突，可從頁面正常結束舊版，並於系統設定停用舊登入項目。

Windows 翻譯需於 **系統設定 → 隱私權與安全性 → 輔助使用** 授權 `.app`；Input Monitoring 有獨立診斷，不會反覆要求權限。依使用者選擇採免費 ad-hoc 個人測試發行，不申請付費憑證、不公證，也不繞過 macOS 安全核准。

## 保護與限制

- Remote／VM／Game／Disabled 停止本機規則、輸入法守護與切換鍵；HID 的 Terminal／IDE 保留整個實體鍵盤語意；舊 EventTap 預覽仍允許原設定的本機系統快捷鍵。
- 右 Option+P 與緊急 Ctrl+Option+Command+P 是穿透模式中的保留快捷鍵；tap 不可用時請用 Menu Bar。
- Pause 5／15／60 分鐘或至重啟；Secure Input、session/sleep、權限及 timeout 有界恢復。
- Finder 使用 AX role/parent metadata，未知焦點不猜測；Clipboard 只使用 changeCount/types，不讀內容、不讀檔案 URL、不保留歷史。Clipboard 與 Finder IPC 並非原子交易；不能宣稱 move 成功。
- Finder action mailbox 最多 16 筆，請求有期限並綁定前景 PID 與 epoch。完整 down/up 發往目標 PID，private source/marker 防自身循環，沒有全域持續合成 modifier。
- 非 ABC/U.S. ASCII layout 仍原樣通過。選用 IME 模式不表示已可靠知道是否正在組字。
- Remote Profile 只決定不改鍵，不能保證 Client 將 Alt+Tab、Ctrl+Alt+Delete 或 Clipboard 傳至遠端。
- NSWorkspace 與按鍵非原子同步、Finder 焦點競態、IME 組字、各 Client 與真實硬體都須實機驗收。

## 隱私與驗證

不讀取 Unicode 輸入、不保存普通 keyDown 序列、不讀既有 Clipboard payload、不網路上傳。啟用截圖自動複製時只將剛儲存的圖片寫入 Clipboard。診斷最多 128 筆、5 分鐘、只在記憶體保存命中的規則和延遲；普通打字不記錄。唯音模組只保留來源切換狀態日誌與計數，最多兩份約 512 KiB。

測試包含原始設定比對、事件配對與 100,000+ 事件壓測、裝置 ledger、Finder metadata state 和程序內 AppKit menu。這些不能證明實機 CPU/RSS、端到端延遲、Remote 相容性或完整替代完成。詳見 [2026-09-28 正式上線前驗收](Docs/ReleaseReadiness-2026-09-28.md)、[Validation](Docs/Validation.md) 與 [替代驗收](Docs/KarabinerReplacement.md)。

移植輸入法模組採 MIT，聲明見 [VChewingGuard license](Resources/Licenses/VChewingGuard.txt)。Karabiner 原始碼研究的來源與架構界線記錄於替代文件；下載安裝包包含固定版原廠簽署的獨立 Driver/daemon 套件及 SDK/vendor 授權聲明。
