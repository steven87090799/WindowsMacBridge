# Windows Win 鍵統一使用 Option

2026-10-28 依使用者要求，將專案所有代表 Windows Win 的 Command 輸入統一改為 Option。Windows 的框選截圖是 Shift+Win+S，因此在本 App 使用 Shift+Option+S。此設定是本 App 的按鍵語意，不會改寫 macOS 或其他工具的全域鍵盤設定。

| Windows 操作 | Mac 輸入 | 行為 |
| --- | --- | --- |
| Win+Shift+S | Shift+Option+S | 框選、複製圖片 |
| Win+PrintScreen | Option+PrintScreen | 全螢幕存檔並複製 |
| Alt+PrintScreen | Command+PrintScreen | 擷取目前視窗並複製 |
| Win+E／L | Option+E／L | Finder／鎖定 |
| Win+R／I／Tab | Option+R／I／Tab | 依各自開關執行搜尋／系統設定／Mission Control |
| Alt+Tab／F4 | Command+Tab／F4 | 原生切換器／關閉目前視窗 |
| Alt+左右鍵 | Command+左右鍵 | 瀏覽器與 Finder 的上一頁／下一頁 |
| Ctrl+C／V 等 | Ctrl+C／V 等 | 仍輸出 macOS 原生 Command+C／V 等 |

原生 macOS 的 ⌘⇧3／4／5、App 選單快捷鍵、輸入法切換熱鍵與 Ctrl 規則的 Command 輸出仍使用正確的 Command。Command+Shift+S 保留原生另存新檔語意；Ctrl+Shift+S 轉成 Command+Shift+S 後不會誤觸截圖。

## 設定與全部輸入路徑

- `WindowsKeyModifier` 只提供 Option；舊 JSON 中的 `command` 會解碼為 Option，下次正常儲存寫回 `option`。未知值仍拒絕，損壞設定仍安全停用。
- 新安裝、缺少欄位的舊設定、推薦設定與一鍵設定都使用 Option。保留各 App／來源／裝置偏好、Fn／Ctrl、截圖與明確關閉的功能設定；不需清除偏好。
- 一般 EventTap、裝置 HID、UC 目的端規則、截圖攔截器、原生截圖轉換、離線預覽與效能檢查工具使用相同 Win／Alt 定義。HID 不再交換 Option／Command。
- 本機與遠端切換器按 Command（Alt）追蹤左右側及釋放，Option（Win）不再啟動 Alt 切換配對。
- 明確「原始 Windows 按鍵」的遠端來源使用相同對應。已辨識 Google CRD／Apple VNC 自動來源接受受支援的 Option／Win 組合，仍保留已是 Command 的 Mac 快捷鍵及 Option 文字導覽。
- 未知自動來源不推測 Windows 語意；Remote Windows／VM 與原樣通過模式保持原始輸入。程序身分驗證、callback 邊界、mailbox 與 MacBook 內建 Fn／Ctrl 交換範圍維持原契約。

## 驗證

自動測試涵蓋舊 Command 設定遷移與其他偏好保留、一般／HID Win 動作、截圖 down／repeat／up、原生 Command 輸出、兩種 tap 順序、遠端明確／自動／未知來源、左右 Command 切換釋放與原樣通過保護。

2026-10-28 本機結果：

- `bash scripts/test.sh`：554 項通過，包含獨立程序的 2 項記憶體回歸。
- `bash scripts/test.sh -c release`：554 項通過，包含相同記憶體回歸。
- 安裝與回滾 66 項、資源監測 6 項、背景復原 13 項 Python 測試通過。
- Release App 建置、簽章驗證、App／復原元件自我檢查通過；使用 macOS 27 SDK，最低 macOS 14。啟動自我檢查的 OCR 框架清單為空。
- 離線產生 20 張介面檢查圖；已查看規則預覽與最小設定視窗，Option+Shift+S 顯示框選截圖，Command 的 macOS 輸出仍正確。
- 封裝 App 的 `--ui-resource-check` 通過：306 個視窗／檢視弱引用全部釋放，保留 0 個。這是合成介面檢查，不代表完整 App 或實機輸入的效能驗收。

本機產物是來源已修改的開發版，維持 1.0.2（66）版本資訊；沒有發佈或替換 `/Applications` 的已安裝版本。

實體 Shift+Option+S、外接鍵盤既有換位，以及兩方向螢幕共享／通用控制仍需依 [人工驗收](../Resources/AcceptanceGuide.md) 與 [雙機步驟](../Resources/TwoMacAcceptance.md) 測試。歷史文件中的 Win＝Command 記錄不代表這次修改後的行為，也不轉換為新的實機驗收證據。

Windows 快捷鍵來源：[Microsoft 官方快捷鍵說明](https://support.microsoft.com/en-us/windows/hardware/input-devices/windows-keyboard-tips-and-tricks)。
