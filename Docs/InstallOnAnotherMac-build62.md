# WindowsMacBridge 0.6.0 build 62：在另一台 Mac 安裝

## 適用範圍

此安裝包適用 Apple Silicon（M 系列）Mac，App 最低系統需求為 macOS 14。不是 Intel／Universal Binary 版本。build 62 的實機驗收是在本次 MacBook 的 macOS 27.0.1 完成，不能視為每一款 Mac 與每個舊系統均已實測。

## 搬機步驟

1. 解壓縮 ZIP，把完整 `WindowsMacBridge.app` 拖入另一台 Mac 的「應用程式」。不要只複製 App 裡面的執行檔。
2. 開啟 App，保持預設的一般模式。此模式的 Fn／Ctrl、Windows 快捷鍵與接收端通用控制處理均在 App 內，無須另裝 Karabiner、Homebrew、Xcode、Root helper 或 Driver。
3. 在新 Mac 核准 WindowsMacBridge 的「輔助功能／裝置控制和資料取用」與「輸入監控」，回 App 確認已取得。macOS 要求重開 App 時完成重開。需要截圖自動複製，再核准螢幕錄製。這些核准不能隨安裝包搬移或由程式預先核准。
4. Windows 模式總開關保持開啟。在 MacBook 上如要交換 Fn／地球鍵與左 Ctrl，明確開啟「MacBook 鍵盤模式」；新安裝此項預設關閉。Mac mini 與外接鍵盤不做此交換。Windows 鍵位置預設 Command，可依該鍵盤實際輸出調整。
5. 如果另一台 Mac 已安裝 Karabiner，而且它接管內建鍵盤，需在 Karabiner Devices 對內建鍵盤關閉 Modify events。本次在原 MacBook 做過的 Karabiner 放行設定不包含在 App，也不應把原電腦的裝置設定或還原 journal 複製到新 Mac。沒有安裝 Karabiner 的電腦不需要為 WindowsMacBridge 安裝它。
6. 使用通用控制時，先讓 macOS 的通用控制正常連線；需要 Windows 相容快捷鍵的兩台 Mac 均安裝 App、完成各自授權。用兩個方向各測一次 Ctrl+C／V。App 不會替使用者設定 Apple Account 或通用控制。
7. 在新 Mac 的文字編輯反白測試文字，以實體鍵盤測 C／X／V／A。MacBook 另測原本左 Ctrl 已成為 Fn，並確認關閉交換或正常退出後還原。「已寫入映射」只是屬性讀回，實體行為以這一步為準。

## 已封裝的元件

| 元件 | 位置與用途 |
|---|---|
| 主 App／一般模式引擎／修復 | `Contents/MacOS/WindowsMacBridge`；包含 build 62 的重複 Ctrl 事件修正 |
| 規則與 App metadata | `Contents/Resources/WindowsMacBridge_BridgePlatform.bundle` |
| Finder Sync 擴充 | `Contents/PlugIns`；一般複製貼上不要求啟用此擴充 |
| 使用與驗收說明、授權文字 | `Contents/Resources` |
| 選用進階 HID runtime／安裝器 | runtime 由同一主 App 的執行檔提供，安裝／移除腳本位於 `Contents/Resources/BackendPayload` |
| 選用 VirtualHID Driver | 同一 BackendPayload 內包含官方 Karabiner DriverKit VirtualHIDDevice 8.6.0，以及 7.3.0 的交易復原材料；不是自行撰寫的 Driver |

封裝 Driver 的安裝材料，不等於已安裝或啟用 Driver。一般模式不安裝、不啟用這些進階元件；只有明確選擇進階 HID 並執行安裝時，才會要求管理員驗證及 macOS Driver 核准，可能需要重新開機。本次沒有在原 Mac 安裝它們，也沒有用安裝進階 Driver 來解決本次 Fn／複製問題。

OCR 維持停用，App 不包含 OCR worker，也不載入 OCR framework；原始碼仍保留在 repository。

## 不會包含的機器狀態

此包不含原 Mac 的權限核准、登入項目核准、使用者偏好、Karabiner 個人設定、鍵盤還原 journal 或通用控制連線狀態。每台 Mac 重新偵測自己的內建鍵盤並建立自己的還原紀錄。

目前 App 使用 ad-hoc 本機簽章，未取得 Developer ID 簽章與 Apple 公證。跨機首次開啟或重新編譯後，macOS 可能要求額外確認或重新授權；這不是「安裝檔已封裝」能消除的限制。正式對外發佈的信任流程仍需有效的 Developer ID 與公證，請勿關閉 Gatekeeper／SIP 或重設全部 TCC 來迴避。

## 此包的驗證範圍

build 62 程式已通過 524 項自動測試，本次 MacBook 的內建 Fn+C／X／V／A、左 Ctrl→Fn 與另一台 Mac 外接鍵盤透過通用控制送入的 Ctrl+C／V，已由使用者實測通過。完整封裝另檢查 ZIP 完整性、解壓後簽章與自我檢查、Driver 安裝材料的固定 SHA256，以及原生執行檔的系統動態函式庫依賴。

這些封裝檢查不是乾淨新電腦的實機安裝測試，也不代表已驗證進階 HID 的安裝／Driver 啟用。一般模式是這次已實測的使用方式。
