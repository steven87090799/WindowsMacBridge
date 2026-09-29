# 0.5.12 保護與一般使用者情境檢查

0.5.12 的 MacBook 新安裝會依主機型態預設開啟 Fn／左 Ctrl 交換。它使用 Apple 的逐 HID 鍵盤服務映射，只在本機實體內建鍵盤服務寫入並讀回驗證；外接鍵盤、Mac mini 和通用控制虛擬鍵盤均不修改。使用者明確關閉的舊設定不被升級覆蓋。這讓內建和外接鍵盤交替輸入時不必為 Fn 交換手動切換；EventTap 的 Win／Alt 訊號仍是整臺 Mac 的設定，兩把鍵盤若送出不同修飾鍵，需分別校準或切換，不能由 Quartz 事件可靠推得來源裝置。依據 [Apple TN2450](https://developer.apple.com/library/archive/technotes/tn2450/) 的逐服務映射與重啟清除特性。

## 本版 Windows 鍵位檢查

舊規則將 Win+E／Win+L 視為 Option，截圖卻只認 Command，Alt+Tab／Alt+F4 又寫死 Option。在這臺 Mac 的實際鍵盤排列下，實體 Alt 送出 Command，造成 Shift+Alt+S 誤觸截圖；這是程式內部的邏輯鍵位定義不一致。現在以持久保存的「這臺 Mac 收到的 Windows 鍵」選擇 Win 來源，Alt 專用操作只用另一個修飾鍵，Ctrl 文字鍵不變。桌機舊設定預設 Option，MacBook 舊設定預設 Command，使用者明確存過的選擇優先。截圖與新增的三個 Win 操作在受保護的 App Profile 原樣通過；沒有增加裝置掃描或按鍵日誌。

依 [Microsoft Windows 快捷鍵](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec) 和 [Apple Mac 快捷鍵](https://support.apple.com/en-au/102650)，可直接對應且不需攔截一般文字的 Win+R／Win+I／Win+Tab 已加入各自關閉的開關，分別對應 Spotlight、系統設定和 Mission Control。這些是類似操作，不是 Windows Run 對話框或 Task View 的逐項複製；⌘Space／⌃↑ 若由使用者改過，應以 macOS 的設定為準。[公開 Karabiner Windows 設定](https://github.com/venkatarangan/karabiner-mac-to-windows) 也記錄了 Win／Alt 在外部映射後反轉的常見現象，但此 App 不修改其他工具或系統鍵位。

## 這版已修改

- 截圖生命週期有獨立 token：關閉／重開／退出不會使上一輪截圖重新取得剪貼簿寫入資格。單一截圖保留至原生工具或圖片 worker 結束，不疊開多個框選。圖片檔保留。
- 截圖 Tap 恢復沿用核心 RecoveryPolicy，60 秒內第三次停用停止自動重試；主執行緒重建工作合併，錯誤在設定可見。無新增長期計時輪詢。
- 圖片轉換移出主執行緒，NSImage／bitmap 不跨執行緒共享；只回傳不可變 PNG／TIFF Data，局部 autorelease pool 釋放暫存物件。PNG 不再二次編碼。依據 Apple [Thread Safety Summary](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html)。
- 保留既有權限與 Secure Input 檢查頻率，輸入與 UI 計時器加入 tolerance 以便系統合併喚醒；輸入檢查每輪建立局部 autorelease pool，UI timer 直接在主 actor 執行，移除每輪額外 Task。依據 Apple [Minimize Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)。
- Fn／Ctrl 關閉且無還原紀錄時不列舉服務，Mac mini 不註冊內建鍵盤通知；手動檢查可以重新註冊失敗的通知，無重試輪詢。畸形／Boolean／小數映射拒絕套用。
- 統計遷移完成後不再讀取舊 App 的偏好 domain，保留使用者要求的統計接續、去重及 MIT 聲明。
- CI 增加最佳化模式的原生通知生命週期測試，涵蓋先前 debug 測試未捕捉的橋接物件崩潰。

## 常見問題與目前處理方式

| 使用情境／問題 | 已有保護或本版處理 | 仍要確認的部分 |
| --- | --- | --- |
| 更新後授權紅叉、快捷鍵沒有作用 | 真實原生授權清單與直接連結；不把點連結當授權 | 免費 ad-hoc 簽章更新可能需重新核准 |
| 手動切換輸入法又被切回唯音 | 保留手動選擇、定時／直到手動恢復的守護暫停 | 各輸入法與實體切換鍵 |
| Shift+Ctrl+S 被當成截圖 | 原始 Win／Command 熱鍵先處理，自己的翻譯事件排除 | 實體鍵位、外部映射、兩個 Ctrl |
| Shift+Alt+S 被當成 Win 截圖 | 截圖、Win+E／L 與 Alt 專用功能採同一份邏輯鍵位選擇；只接受指定的單一修飾鍵 | 外接鍵盤與通用控制換來源時，接收端需核對實體鍵位 |
| Win+R／I／Tab 不像 Windows | 各自選配原生 Spotlight／系統設定／Mission Control，保護 Profile 原樣通過 | 系統已改動的 Spotlight／Mission Control 快捷鍵；實體鍵驗收 |
| 截圖途中重開開關，舊圖蓋掉新剪貼簿 | 本版 token 拒絕舊工作，圖片保留 | 實體框選及大圖途中切換 |
| 重複按截圖熱鍵、按 Esc | 單一工作、取消不寫剪貼簿 | macOS 原生框選在不同螢幕的結果 |
| 巨大截圖導致 UI／Tap 暫停 | 本版背景轉換與局部 pool；PNG 重用 | 多螢幕高解析度峰值，不宣稱無峰值 |
| 剪貼簿輸出失敗 | 圖片仍保存，顯示錯誤，不保留剪貼簿歷史 | 系統 Clipboard 寫入不是原子交易 |
| 系統截圖目錄失效／磁碟滿 | 不可寫回落桌面；沒有圖時不複製 | 目錄權限可在檢查後改變，存檔失敗仍可能發生 |
| Tap 反覆停用 | 核心／截圖都有有界重試與可見錯誤 | 使用者放開按鍵後重新啟動 |
| Terminal、IDE、Remote、VM、Game 誤翻譯 | 原 Profile 與 pass-through 規則保留 | 真實 Client、遊戲、VM、HID 與特殊鍵 |
| 放開修飾鍵、失焦、睡眠後卡鍵 | press ledger、neutral recovery、session 暫停 | 實體 unplug、sleep/wake、登入 |
| Fn 模式影響外接或通用控制 | 僅本機實體 MacBook 內建服務；虛擬／外接排除 | 兩個來源方向分開驗收，Apple 不保證自訂映射傳送階段 |
| Fn 與系統／Karabiner 映射重複 | 拒絕衝突、讀回驗證、保存自己的還原紀錄 | 外部工具可在檢查後修改，沒有原子 CAS |
| 強制終止後 Fn 暫存映射還在 | 同 boot 重啟還原紀錄；重新開機清除原生暫存映射 | 強制終止不能保證即刻還原，需重開或重啟 |
| Finder 文字欄誤刪／剪下過期 | 焦點只讀 role／parent，未知不猜；move 有期限且檢查 Clipboard 版本 | Finder 各檢視、焦點競態、原生確認 |
| Alt+F4 有未儲存文件 | 原生 Cmd+W／Q，保留 App 確認，最後視窗退出模式預設關閉 | App 特殊／輔助視窗的主要視窗判定 |
| 最小化、多螢幕 Alt+Tab | 視窗獨立 MRU，放開 Alt 才切換；縮圖選配 | Spaces／全螢幕、App AX 支援不完整 |
| RAM 看起來很高 | RSS 與 physical footprint 分開；不把全機 swap 歸因 App | 長期同版本背景樣本與輸入負載，短樣本不足 |

## 建議下一步的實用功能（尚未實作）

| 優先度 | 建議 | 使用者得到的幫助與資源界線 |
| --- | --- | --- |
| 高 | 30 秒按鍵位置校準 | 只顯示修飾鍵／keycode，明確開始停止、不存文字；找出 Win／Ctrl／Fn 外部映射衝突，不能從普通 EventTap 猜裝置來源 |
| 中 | Win+D／Win+方向鍵／Print Screen | 顯示桌面、視窗排列及全畫面截圖常見；macOS 原生快捷鍵與多螢幕／Fn 差異大，應先以實體鍵和 OS 版本驗收，再各自提供開關 |
| 中 | Win+V 剪貼簿歷史 | Windows 常見但涉及私人資料；若要加入，必須明確啟用、限制保留、提供清除，不應在本版暗中讀取既有剪貼簿 |
| 高 | 一鍵匯出可預覽的診斷摘要 | 版本、授權、功能狀態、同 PID 資源快照；先排除路徑、視窗標題、文件、輸入內容，按下才匯出 |
| 高 | 設定備份與還原預覽 | 升級前可回看變動、保留 Profile；只保存本 App 設定，匯入前 schema 驗證，不改 TCC |
| 中 | 截圖成功提示與手動重試複製 | 只由使用者點擊最近一次本 App 已儲存的圖；不掃資料夾，不讀取剪貼簿歷史 |
| 中 | App 規則快速搜尋與衝突說明 | 清楚列出目前 Profile、哪個功能會通過與原因；開設定時查詢，不加入背景掃描 |
| 中 | 簽署／公證的穩定發行管道 | 處理已觀察到的更新後身份／系統核准問題；需要正式簽章條件與發行驗證，不能承諾完全免授權 |
| 低 | 原生卸載／還原報告 | 先顯示本 App 擁有的映射、登入註冊與偏好；選擇清除才執行，不刪其他工具資料 |

## 清理判斷

舊版唯音程序探測已移除；現存 VChewingGuard 字樣是必要的來源授權與一次性統計 migration。這版移除遷移完成後的重複舊 domain 讀取、空 Fn 模式的服務讀取／通知，以及 UI 計時器的額外 Task。沒有移除現有 Profile、選用 HID、測試、還原紀錄或保留統計，以免破壞使用者資料及裝置恢復。

## 驗證界線

單元測試、原生通知註冊、建置／簽章及 CPU 樣本分開記錄。未實測的實體按鍵、MacBook Fn／Globe、通用控制雙向、Remote／VM／HID、登入／睡眠與長期效能，均不算驗收通過。這臺主機是 Mac mini，沒有可測的實體內建 MacBook 鍵盤。資源數據與發行結果見 Validation 與 release／PR。
