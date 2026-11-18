# WindowsMacBridge 單一 App 安裝

使用完整 DMG，將 WindowsMacBridge 拖進「應用程式」，再從那裡開啟。預設一般模式逐項引導輔助功能與輸入監控，不安裝背景元件、不要求管理員密碼，也不連線 HID 服務。

在權限分頁逐項核准輔助功能與輸入監控，返回確認綠燈；首次使用自動複製截圖時，依提示核准螢幕錄製。開機自動啟動與 MacBook Fn／Ctrl 交換由一般設定的開關控制。

只有明確開啟「進階選項」並選 HID，才使用面板的安裝按鈕準備內含背景元件及已簽署的官方 Driver；此時才需要管理員驗證、輸入監控及 Driver 核准。輸入監控只授權 WindowsMacBridge，沒有獨立 HID Helper App。官方 Driver 的系統名稱是 .Karabiner‑VirtualHIDDevice‑Manager；核准／重開機由 macOS 決定，安裝成功不代表已核准。

共享 Driver 不降版、不移除其他軟體使用的服務。未知 ABI 或簽章不符時停止安裝；失敗保留記錄並嘗試還原，更新中斷保留私人 journal 供下一次安裝復原。

## 開發者停止與移除

從選單列暫停或正常結束。要移除本 App 的背景元件，請使用進階面板的移除功能。這會走完整的停止、釋放與移除流程，保留主 App、設定和共用官方 Driver／服務。原始碼中的舊 `.command` 檔案屬於歷史流程，現在的單一 App 安裝從進階面板操作。

root launchd 只執行 root-owned 的同簽章 WindowsMacBridge 副本與 `--hid-service`，不執行可被使用者取代的 Applications 路徑。舊 HIDHelper launchd／Mach label 只保留作內部相容，並非另一個權限 App 身分。更新時保存、還原舊版 Helper 或新版 runtime，成功才移除舊 Helper App。

實體鍵盤、UC、Remote、系統權限重開及資源峰值仍需按驗收指南測試。單元測試與 CI 不替代實機驗收。
