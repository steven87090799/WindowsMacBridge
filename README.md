# WindowsMacBridge

Windows 快捷鍵相容層與唯音／ABC 輸入法輔助，整合成一個 macOS Menu Bar App。**0.3.0 開發預覽，尚不能完整取代 Karabiner。** macOS 14+，目前執行後端仍為 User Space CGEventTap。

主專案是這個 repository；`vchewing-input-helper` 已移入 `InputSourceCore` 與 `InputSourceSupport`，不需同時執行兩個 App。[整合與遷移](Docs/ProjectIntegration.md)。

## 0.3 新增

- 29 組一般快捷鍵與 Ctrl+方向鍵／Home／End／刪除，19 組瀏覽器專用規則。
- 右 Option+P 切換穿透；左 Option+E 開 Finder、左 Option+L 鎖定、Ctrl+Shift+Esc 開活動監視器。
- 可選 Finder Ctrl+X/V 剪下移動、Enter 開啟、F2 改名等操作。只在可確認的檔案列表執行檔案動作；剪下 intent 綁定剪貼簿版本與 Finder PID，有效 5 分鐘。
- 可選唯音／中文 IME 實體鍵位快捷鍵，需要底層 ABC/U.S.；組字相容性仍待实機測試。
- Remote regex 與 executable path fallback、擴充 IDE 保護、瀏覽器辨識。
- 原始 78 條設定 fixture、HID 裝置 metadata 診斷、可測試的 device-scoped modifier ownership 核心。

完整差異與固定 revision 的 Karabiner 原始碼研究見 [替代實作與驗收](Docs/KarabinerReplacement.md)。

## 尚未完成的替代功能

**內建鍵盤限定、Fn/左 Ctrl 與左右 Option/Command 整鍵交換、亮度鍵、Alt+Tab 尚未接通硬體後端。** HID 狀態模型不等於已完成 driver。新的安裝預設使用要求的「內建或 Apple 1452/834」範圍；目前會明確停止翻譯，避免擅自影響其他鍵盤。

要試用本次快捷鍵功能，須在設定選擇「所有鍵盤（快捷鍵預覽）」並啟用 Windows 快捷鍵。這與完整替代的裝置隔離要求不同。不要同時套用相同 Karabiner 規則，以免重複映射。

完整替代後端需要指定 IOHIDDevice capture、Privileged helper、DriverKit virtual keyboard。可以評估重用官方已簽署的獨立虛擬 HID driver；自行發行 driver 則涉及自己的 entitlement 與 provisioning。本 repository 尚未安裝或打包任何 root helper／driver。

## 建置與執行

需要 Swift 6 工具鏈（Xcode 或 Command Line Tools）。目前 Swift targets 沒有第三方套件。

```sh
bash scripts/test.sh
bash scripts/build-app.sh
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

- Remote／VM／Game／Disabled 停止本機規則、輸入法守護與切換鍵；Terminal／IDE 保留 Ctrl 語意，但允許原設定的本機系統快捷鍵。
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

移植輸入法模組採 MIT，聲明見 [VChewingGuard license](Resources/Licenses/VChewingGuard.txt)。Karabiner 原始碼研究的來源與架構界線記錄於替代文件；尚未 vendoring 其 driver 或 daemon。
