# 雙模式重構與外部審查核對

來源基準：main `4c8369d`（PR #9）；這份文件對應 build 43 的雙模式修復候選版。外部報告的行號不能當成目前來源證據，以下以 production code 的行為核對。尚未執行實體鍵盤、第二臺 Mac、Windows Host、記憶體峰值或 Driver 故障注入驗收。

## 已確認錯誤與修改

| 外部項目 | 核對結果與處理 |
|---|---|
| 1 模式隔離 | 原預設為 HID，啟動會建立 client／探測背景元件，而且首次設定會強制 HID。改成 EventTap 預設與持久化的明確進階開關；舊 HID 選項不構成新模式的同意。一般模式不建立 HID client、探測 Driver 或自動提權。只註冊 closure 本身不是 XPC 連線證據，但其後的啟動／publish 路徑確實有問題。 |
| 2 Finder 根目錄 | 確實把擴充作用於 `/`。已永久改成空清單並停止主 App 的 Finder Sync 啟用通知。Ctrl+X／V、F2、Delete 由 ShortcutActionDispatcher 執行，不依賴擴充。實際彩球是否由此造成沒有量測證據。 |
| 3 releasePending | 原逾時會永久保留 stop 狀態。現在逾時／斷線銷毀舊 XPC lease、清除旗標，逾時仍明確顯示「未獲確認」。EventTap 不再被舊 HID 的旗標阻擋；正常切換先釋放 ownership 再銷毀 client。這不能冒充 Driver 的硬體釋放確認。 |
| 4 同步 sleep | C++ 確有 100ms sleep。已移除；關閉實體裝置先於有界的單一 VirtualHID teardown worker，完成後才回覆 stop。共享 dispatcher 的銷毀不再卡住 capture RunLoop。 |
| 5 輪詢 | 原 client、capture、EventTap 都有 250ms timer，host 另有 1s timer。已改為設定、App／session、裝置匹配及 Driver callback 驅動；遠端持鍵遺失使用單次 60s deadline，HID 只有尚有 held output 時使用單次 1s 安全檢查，所有鍵放開即停止。一般模式閒置沒有固定輪詢。 |
| 6 生命週期 | 原已有 stop 的 TIS RemoveObserver/release 及 Carbon RemoveEventHandler，報告「缺乏清理」不精確；但 passRetained(self) 仍可在未呼叫 stop 時自我保留。改成弱 owner 通知 token，加入 deinit 清理與生命週期回歸。 |
| 7 hot path | 規則 ID split 確在每次查表後執行；改成建構 ShortcutRule 時一次分類。Secure Input 不能只快取 App 切換：同一 App 中也能開啟。保留每個真實輸入一次原生安全檢查，移除同一事件派送的第二次查詢，狀態／權限整理移出 callback。 |
| 9 喚醒映射 | 原 configure 已間接 refresh，但現在 didWake 與 session 恢復明確重查映射；待放開按鍵改由按鍵活動通知重試，不閒置輪詢。內建判斷原本就要求 builtIn=true，外接、虛擬、UC 服務仍排除。 |
| 11 UI | 一般設定保留六項常用控制及原上方分頁；診斷、後端、背景元件安裝／移除及裝置偏好需要明確進階開關。一般權限頁只列輔助功能，用原生 AX 與 posting 結果共同確認，不能把 AX=true 當作輸出權限已通過。 |

## 報告不適用或已具備

- **8 截圖重複 bitmap**：目前 ScreenshotCaptureDriver 執行 `screencapture -t png`，PNG 通過 ImageIO metadata／尺寸／深度預算後直接以 mapped data 寫入 public.png；並沒有報告所稱 CGImage→NSBitmapImageRep→TIFF→PNG 管道。TIFF／PDF 才需要單次轉 PNG，PDF 內嵌／inline raster 已有資源與解碼預算。這輪移除一般截圖資料夾 watcher 與 30 天修復 timer，改為自己的一輪 capture／temporary file／clipboard lifecycle。不能直接把 CGImage 傳給 NSPasteboard，pasteboard 需要編碼 representation。完整 App＋子程序＋系統 clipboard 峰值仍未量測。
- **10 CRD Host**：RemoteAdapterCatalog 原本已用 Google 的 signing ID＋Team ID 辨識 host，RemoteSourceRouter 的 automatic 已轉譯 raw Ctrl、保留 Command。不能把所有前景 Remote client 改成 Translate，否則 Mac→Windows 的 Ctrl 會被破壞。這輪補 EventTap 對已辨識 UC 接收事件的目的端處理，並讓 incoming host 在只具 AX 的 EventTap 路徑也能運作。隱藏 producer PID 仍是支援缺口。
- **12 macOS 27**：此實機 `sw_vers` 為 macOS 27.0／26A428，不是假想版本。保留實際系統頁面名稱與 availability。降成 14／15 會把新的設定標籤誤用到舊系統。

## 支援缺口與規格需修正之處

1. 一般快捷鍵啟動只引導輔助功能；**截圖第一次明確使用仍可能需要螢幕錄製**。AX 不能替代它。Windows／⌘⇧3／⌘⇧4 截圖完成後由本 App 的 lifecycle 直接複製；Esc、Pause、設定／backend／session 改變不准舊工作寫 clipboard。Win+PrintScreen 是明確存檔操作，可能觸發桌面資料夾授權，其他截圖用暫存檔、結束即清除。
2. Apple TN2450 正式範例寫 `kIOHIDUserKeyUsageMapKey`，內部 pair 使用 `HIDKeyboardModifierMappingSrc/Dst`，不需特殊權限。本專案保留這個原生 API；`IOHIDKeyboardModifierMappingPairsKey` 只讀來檢查系統既有修飾鍵衝突，不盲寫它或覆蓋其他工具。參考：https://developer.apple.com/library/archive/technotes/tn2450/_index.html 。服務移除／重新開機會清除暫存映射；crash 後要由下次啟動／明確登入啟動恢復紀錄，不能承諾 force quit 當下自動還原。
3. EventTap 沒有可靠的逐鍵盤 ID，也無法對所有 UC／Remote 組合承諾 100%。一般模式只處理已知來源／可確認的目的端；未知來源保持原樣。兩端都裝 App 時，Command／Bridge marker 不再翻譯，UC 丟失 metadata 的真實傳輸仍需驗收。
4. 已有共享 Karabiner Driver 不會為一般模式被停用、改名或刪除。自己的 root runtime 釋放後無 client 會結束，launchd 僅按 Mach service 要求啟動；移除進階元件也保留共享 Driver／服務。沒有 Apple Developer／DriverKit entitlement 時不能發佈自己簽署改名的 dext。
5. 已消除固定閒置工作，不把程式碼審查當作 CPU 穩定 0.0–0.1% 或 whole-process RAM 峰值已達標。測量方法見 AcceptanceGuide。

## 驗證界線

新增／更新 regression 覆蓋：舊 HID 設定不默認開進階、fresh normal 預設、舊釋放旗標不封鎖 EventTap、閒置不安排 timer、XPC 停止逾時、連線 lease 驗證／失效釋放、TIS／Carbon owner 清理。既有 screenshot job／decode／PDF、Finder、modifier、CRD host、自製切換器移除等回歸保留。

依使用者要求不跑整套本機測試；只做必要 Release 編譯與封裝。Hosted CI 的結果另外記錄，不把 CI 通過視為跨機、Driver 升級、硬體交接或資源實測通過。原始碼、封裝、Installed App、實際權限與實機驗收是不同階段。
