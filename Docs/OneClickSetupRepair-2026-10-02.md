# 一鍵安裝、權限與 Windows 截圖修復（0.5.17 / build 34）

此機 build 33 主 App 的鍵盤控制、輸入監控、螢幕錄製已取得；仍不能用 Windows 截圖，不應繼續把原因歸於這三項權限。實體熱鍵未由 reviewer 操作，不能斷言已重現全部失效原因。

已確認錯誤：背景元件的權限要求原本依賴已啟動的 HID 連線，EventTap 或缺主 App 權限時按第 6 列沒有作用。改為經身分驗證的權限專用 IPC；不 configure、不接管鍵盤、不取代現有鍵盤連線。要求後另外使用 IOHIDCheckAccess 確認，不能把要求 API 回傳當成綠勾。

Driver 管理程式原廠 `activate` 入口是命令列程序，不處理 Cocoa 的 reopen AppleEvent；原本透過 NSWorkspace 啟動會出現 errAETimeout (-1712)。改為驗證原廠 Team／bundle signature 後直接執行 activate；最多一個程序，120 秒逾時只終止自己啟動的管理程序。已登錄且等待使用者核准時直接開啟系統設定，不重複啟動。Driver 的 registered 與 activated enabled 仍分別判斷，已安裝不等於已授權。

安裝完成首次啟動，程式準備 Windows Experience、HID／所有鍵盤、截圖、Finder、文字導覽和視窗快捷鍵；辨識到內建 Apple 鍵盤才自動啟用 Fn／Ctrl。保留其他 App／Remote／裝置規則、手動 Windows 鍵位置及永久刪除選擇。設定損壞時保持停用，不覆寫原資料。安裝頁提供單一「一鍵安裝／修復」；權限仍由使用者核准。第 8 列從截圖資料夾的上一層開始，附在設定視窗上，避免要求選 Desktop 卻開在 Desktop 內。

Win+Shift+S、PrintScreen 框選／全螢幕和 Win+PrintScreen 在 session tap 原地改寫成原生 macOS 截圖鍵，保留原始事件路由，不依賴 annotated 事件目的 PID 才啟動框選，不在來源端另開 App。接收端收到原生截圖鍵不會再套用 Windows 截圖映射。Alt+PrintScreen 保留目的端驗證的視窗擷取路徑。實際 UC／Remote 路由仍需兩台電腦驗收。

圖片先由 macOS 存檔，再經既有檔案觀察、圖片預算與生命週期檢查自動複製；不使用原生 Control 截圖直接寫剪貼簿，以免 Pause 後仍由 OS 完成寫入。已觀察的框選在 Pause／backend／session／權限變更後取消自動複製，取消狀態跨恢復保留，下一次新的截圖快捷鍵才解除。原生 UI 本身由 macOS 控制，仍可存檔及按 Esc 取消。浮動縮圖可能延後存檔数秒；選 Preview／Mail 等不在截圖目錄產生新檔的系統目的地不在自動複製範圍。

资源：一般按鍵在 callback 早期通過，只有相關截圖鍵才做來源判斷；持鍵狀態最多兩筆。復原工作按 tap 世代合併，60 秒內第三次失敗停止重試；沒有新增高頻 timer、目錄輪詢或整份檔案掃描。Driver／helper 權限檢查在 callback 外，有程序／連線數及逾時上限。

針對性檢查：NativeScreenshotMappingTests、BackendOwnershipTests、DriverApprovalTests、oneClickSetup 設定保存、ScreenshotRuntimeTests 與資料夾存取，共 19 項通過；另補「框選後 Pause／resume，舊檔才出現」的實際 manager／私人剪貼簿回歸通過。Release 建置與封裝另行完成。未執行完整套件、真實熱鍵、跨機、TCC 核准、Driver 重開機或記憶體峰值驗收。

此機安裝：內含安裝器回傳 0；App 與 helper 均為 build 34，沒有 `.install-recovery`，GUI 已自動開啟「安裝與權限」八項清單並確認預設準備完成。2026-10-02 21:25 的原生檢查顯示第 4、5 項已核准；第 1、2、3、6 項未取得，第 7 項待核准，第 8 項未檢查。更新的臨時簽章不能沿用前一版全部授權，仍需使用者逐項核准。目前未將實體 Windows 截圖操作視為驗收通過。

單一 App 產物：`build/download/WindowsMacBridge-0.5.17-preview.6-app-macos-arm64.zip`。
