# WindowsMacBridge

Windows 快捷鍵相容層與唯音／ABC 輸入法輔助，整合成一個 macOS Menu Bar App。**0.4.0 HID 整合測試版，尚待實機驗收。** macOS 14+；支援裝置 HID 後端與 CGEventTap 快捷鍵預覽。

主專案是這個 repository；`vchewing-input-helper` 已移入 `InputSourceCore` 與 `InputSourceSupport`，不需同時執行兩個 App。[整合與遷移](Docs/ProjectIntegration.md)。

## 0.4 HID 整合測試版

App 已接上驗證身分的 XPC、指定 IOHIDDevice 擷取與官方 VirtualHID 輸出。下載包包含 App、helper、官方已公證的 Driver 套件、安裝／停止／移除工具。App/helper 仍是未公證的 ad-hoc 開發版，尚待實體鍵盤與遠端驗收，不能宣稱完整替代完成。

- 29 組一般規則、19 組瀏覽器規則、Finder 剪下／移動與系統動作。
- HID 後端只抓取支援的內建或 Apple 1452/834 服務；Fn／左 Control、左右 Option／Command 交換、完整持有的 Alt+Tab、consumer 亮度增加→Enter。
- Terminal／IDE／Remote／VM／Game／Disabled 的 HID 事件原樣通過；保留右 Option+P 與緊急暫停。不同 descriptor、Caps Lock／Globe／IME、Remote Client 仍需逐項驗收。
- 與唯音／ABC 輸入法守護整合；CGEventTap 預覽後端可另選，兩個後端不會同時翻譯。

安裝與實機檢查：[READ-ME-FIRST](Resources/Installer/READ-ME-FIRST.md)。接線、授權與驗收邊界：[HIDIntegration](Docs/HIDIntegration.md)。原始 78 規則與 upstream 研究：[KarabinerReplacement](Docs/KarabinerReplacement.md)。新安裝預設停用，不會在下載／建置時接管鍵盤。

## 建置與執行

需要 Swift 6 工具鏈（Xcode 或 Command Line Tools）。主程式沒有第三方 Swift 套件；HID helper 使用固定 revision 的官方 C++ VirtualHID SDK。

```sh
bash scripts/test.sh
bash scripts/build-app.sh
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

Windows 快捷鍵、唯音守護、輸入法切換键預設停用。唯音功能使用 TIS 與 Carbon，不需要 Accessibility，且需先安裝唯音。若 VChewingGuard 還在執行，輸入法頁會顯示衝突，可從頁面正常結束舊版，並於系統設定停用舊登入項目。

Windows 翻譯需於 **系統設定 → 隱私權與安全性 → 輔助使用** 授權 `.app`；Input Monitoring 有獨立診斷，不會反覆要求權限。打包預設 ad-hoc 簽署，未公證；固定路徑和正式 Developer ID 簽署仍是正式發佈要求。

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

不讀取 Unicode 輸入、不保存普通 keyDown 序列、不讀 Clipboard payload、不網路上傳。診斷最多 128 筆、5 分鐘、只在記憶體保存命中的規則和延遲；普通打字不記錄。唯音模組只保留來源切換狀態日誌與計數，最多兩份約 512 KiB。

測試包含原始設定比對、事件配對與 100,000+ 事件壓測、裝置 ledger、Finder metadata state 和程序內 AppKit menu。這些不能證明實機 CPU/RSS、端到端延遲、Remote 相容性或完整替代完成。詳見 [Validation](Docs/Validation.md) 與 [替代驗收](Docs/KarabinerReplacement.md)。

移植輸入法模組採 MIT，聲明見 [VChewingGuard license](Resources/Licenses/VChewingGuard.txt)。Karabiner 原始碼研究的來源與架構界線記錄於替代文件；下載安裝包包含固定版原廠簽署的獨立 Driver/daemon 套件及 SDK/vendor 授權聲明。
