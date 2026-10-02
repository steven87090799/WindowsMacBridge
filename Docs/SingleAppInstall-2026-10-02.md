# 單一 App 安裝結果

2026-10-02：依使用者要求，將安裝入口、helper、官方 Driver 套件與既有交易／回復流程收進一個 App。沒有執行測試套件或鍵盤／跨機驗收，只做必要 Release 建置、簽章／封裝檢查與實際安裝。

最終候選：WindowsMacBridge 0.5.17（32），preview.4。ZIP 解壓後只有 WindowsMacBridge.app；不需要另外執行外部 Install.command。

## 安裝流程

1. 開啟 App 的「授權」頁，按「安裝／修復背景元件」。
2. App 正常結束，獨立 launcher 在 bundle 外建立暫存快照，要求管理員認證，交给既有 root installer 驗證與安裝。
3. 完成後開啟 /Applications/WindowsMacBridge.app。
4. 首次安裝只安裝 Driver 檔案。使用者再按「啟用／核准 Driver」，由 NSWorkspace 啟動正式安裝的原廠 Manager，參數為 activate。
5. 使用者另行開啟鍵盤控制、helper 輸入監控及需要的螢幕錄製。開啟 Manager 不等於 Driver 已啟用，必須觀察實際 HID Ready。

Driver 與 Manager 保留原廠簽章、名稱及圖示；Bridge helper 名稱為 WindowsMacBridge HID Helper。不要把 build/consistency-verification/driver-package 下的拆包副本加入 Bridge 權限。

## 此機結果

- /Applications/WindowsMacBridge.app 已更新到 0.5.17（32），從該路徑啟動。
- /Library/Application Support/WindowsMacBridge/BridgeHIDHelper.app 的 build 為 32；helper launchd 註冊已建立。
- 官方 Driver receipt 為 8.6.0；共用服務 launchd 註冊已建立。
- 安裝器回傳成功，沒有待復原 .install-recovery。
- Driver 啟用、TCC、HID Ready、實體鍵盤與跨機行為尚未驗收，留給使用者開權限及後續實機操作。

## 修正安裝與授權耦合

先前 preview.2／preview.3 嘗試中，官方 pkg 安裝成功，但後續 Driver 啟用沒有完成，整體交易遂回復；原始記錄未保留足夠啟用錯誤細節，不能判定使用者漏按核准或 Driver manager 的具體失敗原因。

本次只對首次安裝取消「當場完成 OS activation 才能提交安裝」的條件。共用舊 Driver 升級仍保留啟用與失敗回復 gate；沒有跳過版本、簽章、checksum、owner、controller pin 或復原檢查。DeviceCapture 仍須 driverReady 才能觀察／接管實體鍵盤。

安裝 log 不再列印每個 checksum 成功項目；Driver manager 若失敗，既有 runner 的退出碼與最多 40 行尾端記錄會傳到安裝記錄。失敗提示不是成功證明。

新增驗收方法：首次安裝未核准 Driver 時，元件檔案應安裝完成且不接管鍵盤；手動核准後才可能 Ready。管理員取消、未知 Driver、共用舊版升級及中斷回復仍需另行測試。本輪沒有執行這些 regression suites。
