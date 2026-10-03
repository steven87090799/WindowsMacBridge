# WindowsMacBridge 0.6.0（build 43）

## 安裝與使用

1. 點兩下 DMG，先正常結束舊版，把 WindowsMacBridge.app 拖進「應用程式」取代，再開啟。
2. 預設「一般模式」：權限頁只列輔助功能。按「開啟設定」，核准 WindowsMacBridge 後回來重新檢查；需要時正常結束並重開 App。綠燈必須經本版 App 的原生檢查，不以舊版同名開關作為依據。
3. 用 TextEdit 的測試文字試 Ctrl+A／C／V／Z。Terminal 的 Ctrl+C 保留中斷命令；IDE／Remote／VM／Game 依 App 規則保護。
4. Win+Shift+S 或 PrintScreen 框選後直接貼上圖片；⌘⇧3／⌘⇧4 也直接複製，無需開縮圖。首次擷取可能要求螢幕錄製授權；這不是 HID／Root 授權。

一般模式不自動安裝背景元件、不連線 root XPC、不捕捉 IOHID、不啟用 Driver。App 使用 ad-hoc 簽章，更新可能需要重新核准目前版本；沒有 Apple 公證。不要為此關閉 Gatekeeper／SIP 或重設其他 App 的權限。

## 六項一般設定

| 項目 | 新安裝預設／操作 |
|---|---|
| Windows 核心快捷鍵 | 開；複製、貼上、復原、儲存、分頁與文字導覽。Alt+Tab 使用 macOS 原生切換器，沒有 MRU／自製視窗切換器。 |
| MacBook 鍵盤模式 | 關；明確開啟才交換本機內建 Fn／Globe 與左 Ctrl。外接與 UC 虛擬鍵盤不交換。切換前放開所有按鍵。 |
| Finder 檔案操作加強 | 開；Ctrl+X→切資料夾→Ctrl+V 移動、F2 改名、Delete 垃圾桶。Shift+Delete 有確認，舊版明確停用永久刪除的設定保留。文字編輯／未知焦點不會盲刪。無需 Finder 擴充。 |
| Windows 快捷截圖 | 開；Win+Shift+S／PrintScreen 框選，Alt+PrintScreen 當前視窗，Win+PrintScreen 全螢幕存檔＋複製。⌘⇧3／⌘⇧4 使用相同取消／自動複製流程。 |
| 這臺 Mac 收到的 Windows 鍵 | Command；若實際 Win 發出 Option，改選 Option。不是交換整臺鍵盤的 Ctrl／Command。 |
| 開機自動啟動 | 使用系統原生登入項目，只有明確切換才註冊／移除；不因截圖開關而自動申請。 |

上方保留權限、一般設定、唯音與輸入法、App 規則；唯音守護與切換熱鍵預設關閉，保留原輸入來源。自訂 App／來源／裝置與明確關閉的功能設定保留；損壞設定安全停用，不覆寫原資料。

## MacBook 與兩台 Mac

Mac mini 外接鍵盤固定不換；MacBook 只使用內建鍵盤，在 MacBook 開啟 Fn／Ctrl 模式，在 Mac mini 保持關閉。兩端都安裝 App、先使用一般模式，再按 [TwoMacAcceptance.md](TwoMacAcceptance.md) 分別測本機與 UC 兩方向。

原生映射使用 Apple 的 UserKeyMapping service properties；只修改本 App 擁有的 pair，保留其他工具。正常退出／關閉時還原；強制結束可能留下暫存映射，下次啟動依還原紀錄處理，重新開機清除服務暫存。喚醒與內建鍵盤重建會重新檢查。其他工具佔用 Fn／Ctrl 時顯示衝突，不覆蓋。

UC 與 Remote 不是相同來源契約，來源 PID／目標 App 可能缺失；不能承諾每種組合都通過。已知 Google CRD host 的 raw Ctrl 依 Mac 目的端轉成 Command；已是 Command 的事件通過。Mac 上開遠端 Windows viewer 時保持 Ctrl，不要把 viewer 的 App 規則改成 Default macOS。未知來源不猜。

## 截圖權限與取消

第一次明確擷取才可能提出螢幕錄製要求；到「隱私權與安全性 → 螢幕與系統音訊錄製 → WindowsMacBridge」開啟。AX 無法替代這項授權。一般權限頁仍只引導鍵盤的輔助功能，截圖失敗會在一般設定顯示原因與螢幕錄製入口。

一般截圖使用暫存 PNG，直接寫入 public.png 剪貼簿後清除暫存。只有 Win+PrintScreen 明確保存全螢幕圖片到桌面，必要時由 macOS 要求該資料夾存取。沒有監看整個桌面或 Finder `/`。Esc、Pause、功能關閉、backend／session／安全狀態改變會取消舊工作；只有當前一輪可寫入剪貼簿。同時最多一輪擷取，120 秒逾時；權限、程序、磁碟、解碼／編碼錯誤各自顯示。

## 選配進階模式

一般設定 → 展開「進階選項」→ 明確勾選「解鎖進階後端模式」。之後才顯示後端、安裝／移除、Driver、指定鍵盤及詳細診斷。勾選本身不自動提權；選 HID 後，用面板的安裝按鈕準備背景元件，再逐項核准輸入監控與 Driver。所有安裝材料仍在同一 App，不要另外找 HID Helper.app。

系統 Driver 的官方名稱是 `.Karabiner-VirtualHIDDevice-Manager`；沒有自己的 Developer／DriverKit 簽署資格不能冒用或改寫該名稱。共用 Driver 不會因為退出一般模式或移除 WindowsMacBridge 的 root runtime 被刪除。切回一般模式先釋放硬件 ownership／關閉 XPC；新 EventTap 不會被舊 stop 旗標永久封鎖。HID 斷線／Driver teardown 仍需實機驗收。

暫停可用選單列；暫停與正常退出會取消輸入輔助及未完成截圖。診斷只在進階模式明確開啟，5 分鐘到期，記錄規則／時間，不記錄輸入文字。
