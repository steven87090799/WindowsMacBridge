# WindowsMacBridge：人工驗收指南

程序碼回歸／CI、Release 封裝、Installed GUI 授權、實體鍵盤、跨機與資源量測是不同證據。以下尚未實機驗收。用可丟棄文字與檔案，勿在重要文件做故障測試。

## macOS 設定介面（build 55）

以滑鼠及鍵盤切換每個側邊欄項目，確認內容、目前選取及 VoiceOver 標籤一致。測工具列收合／展開及 ⌃⌘S、拖曳分隔線、730×600 最小視窗、表單捲動、關閉後重新開啟。規則預覽的自選修飾鍵在窄視窗可分行，長表格結果可用提示或收合側邊欄閱讀。確認診斷只在進階模式顯示。

分別測亮／暗色、提高對比及減少透明度；截圖縮圖顯示期間切換後兩項時，文字與關閉按鈕仍應清楚。macOS 26 以上用系統 Liquid Glass，macOS 14／15 保留原生材質。離線產生圖只能驗證自有版面，不能取代實際視窗背景折射、滑鼠／鍵盤導覽及輔助使用驗收。既有快捷鍵、截圖自動複製與文字擷取按以下項目另測。

## 最短開始

DMG 拖入 Applications → 一般模式 → 權限頁逐項核准輔助功能與輸入監控 → 原生確認綠燈 → TextEdit Ctrl+C/V。螢幕錄製單獨列出，登入時啟動為選用；一般模式不應要求 Root／Driver，也不應自動註冊登入。首次截圖可能要求螢幕錄製；核准後重開 App 再試。不用安裝 Finder 擴充。

## 1. 快捷鍵與持鍵

Terminal 與 IDE 也測 Ctrl+S／Z／Y／F／T／W、Ctrl+Arrow、Home／End、Alt+Tab／Alt+F4 與截圖，確認套用完整 Windows 相容規則。各 App 是否提供對應命令另行記錄，不以送出 Command 快捷鍵當作功能成功。兩套輸入後端都須驗收。

TextEdit、Safari 各測 Ctrl+A/C/X/V/Z/Y/F/S/P、Ctrl+Tab、Ctrl+Shift+Tab、Ctrl+T/W／Shift+T、Ctrl+Arrow／Shift+Arrow、Home/End/Delete。先複製後按住 Ctrl 再 Tab，確認仍是分頁切換，沒有殘留 Command。左右 Ctrl／Shift／Alt 重疊，字母先放／修飾鍵先放各測一次。按住 Ctrl 在兩個普通 App 來回，重復 Ctrl+C；進入 Remote、Pause、Secure Input、session鎖定後放開鍵，回來新快捷鍵恢復。不要關閉系統的真正安全輸入。

一般模式無法可靠按鍵盤 ID 分流；若另接第二把測試，兩把同按相同按鍵時記錄 aggregate flags 的限制。使用者實際環境是 Mac mini 外接＋MacBook 內建，雙機按下一節。

## 2. UC／Remote／HID 分流

按 [TwoMacAcceptance.md](TwoMacAcceptance.md) 測兩方向，特別是來源 Terminal→目的 TextEdit 的 Ctrl+C、兩端都裝 App、持鍵跨屏。Windows→Google Chrome Remote Desktop Host→Mac mini：在 Mac TextEdit 試 Ctrl+C/V/X/Z/A/S，已是 Command 不再翻譯。Mac→Windows viewer／VM：同樣組合應保持 Windows Ctrl，Alt+Tab 按客戶端轉發設置處理。隱藏 PID、未知復合 HID、混合 Native Mac 裝置與 Remote 手動 profile 各自記錄，未經操作保持「未驗收」。

## 3. Finder 與窗口

兩個測試文件：Ctrl+X→進新目錄→Ctrl+V，應該移動一次，clipboard改變／超過5分鐘不能繼續舊move。F2改名、Delete垃圾桶。文件名文字編輯中的Delete應刪字，未知焦點不盲刪。Shift+Delete確認取消不刪除；確認刪除只用可丟棄文件。Alt+F4只關當前窗口，保留未儲存對話，不退出整個App。一般App亮度鍵不能變Enter。打開多目錄檢查Finder延遲；沒有全磁碟 FinderSync 監控，但流暢度仍須實測。

## 4. 截圖與記憶體

Win+Shift+S／PrintScreen 框選、Alt+PrintScreen 當前窗口、Win+PrintScreen 全屏存檔，完成選區後直接 Ctrl+V／Cmd+V，不應等待系統縮圖消失或貼上上一份內容。CmdShift3 全屏、CmdShift4 選區也走自製預覽與複製；暫停或關閉後恢復系統原生行為。以可丟棄文字設置測試剪貼簿，再截產生的測試圖片確認貼上是新圖，記錄擷取完成到可貼上的時間。

複製成功後右下角應有 320×248 自製預覽，標示「截圖已複製」、貼上提示與關閉按鈕，圖片完整依比例顯示。檢查寬／高／小圖、亮／暗模式與多螢幕邊緣；macOS 26+ 且 SDK 支援時採 Liquid Glass，舊版毛玻璃，減少透明度／高對比下文字與操作仍清楚。預設 5 秒消失，移入時保留，移出重新計時。點圖用系統快速查看放大；連續截圖最多一個預覽及一個快速查看程序。這些快捷鍵不應另顯示 macOS 浮動縮圖。

一般框選／視窗／CmdShift3、4 的暫存 PNG 在預覽或快速查看結束後刪除；Win+PrintScreen 在桌面保留 PNG，關預覽不能刪除。⌘⇧5 的原生截圖及其檔案不由自製預覽管理。Esc 取消保持原 clipboard；框選中→Pause／換 backend／鎖屏／關功能再開，舊結果不得寫入，縮圖準備中暫停／新截圖後不得冒出舊預覽。核准／撤銷 ScreenCapture 不得偽成功；磁碟／程序／解碼／編碼失敗各有錯誤。

展開控制中心／選單列面板（包含螢幕共享面板），保持面板開啟，分別按 Win+Shift+S／PrintScreen；應可框選並貼上面板內容。全螢幕截圖也應可用，Alt+PrintScreen 仍只接受前景 App 的視窗。跨 Mac Universal Control 測試時，來源 Mac 不得因為沒有本機事件接收程序而啟動截圖。

圖片預算覆蓋PNG／TIFF／PDF、PDF嵌圖與inline image，壓縮文件小不表示可無限解碼。記錄5K／4K多屏截圖時 **App＋screencapture＋WindowServer＋clipboard** 的峰值，分開 RSS 與 footprint；現有預算不是整體峰值保證。不要用自動化讀取使用者當前clipboard或屏幕作為測試素材。

## 5. 進階權限與Driver／安裝

只有明確勾進階才安裝／連XPC。逐項授權輸入監控、官方Driver；原生IOHID／driver核對才能綠燈。首裝、與Karabiner共用、更新中斷、timeout、需要用戶批准／重開機、回滾須實機測，fixture通過不算硬件驗收。切回一般應關閉自己的runtime，不停止／刪除其他軟件的共享Driver。權限只改本App，不重設全部TCC；ad-hoc更新重新授權屬於現有簽章限制。

## 6. MacBook 原生映射

僅builtIn=true的本機Apple鍵盤交換Fn／左Ctrl；Mac mini、USB／Bluetooth、UC／virtual不交換。正常退出還原；與他人工具Fn／Ctrl衝突要顯示問題且不覆蓋其他pair。強制退出後下次啓動／登入應處理journal；重開機服務映射清除。睡眠／喚醒、服務重建、持鍵切換與restorePending都實測，不能用property setter返回true就判定成功。

## 7. 輸入法與App模式

ABC與唯音各測組字、選字、Enter／Backspace／Shift／CapsLock，再測試複製。在 TextEdit、Terminal、IDE 分別測左右 Ctrl+C／V／A／X 與原生 Command+C／V／A／X，確認複製、貼上、全選、剪下依 App 可用功能執行；先放開 Ctrl 再放開字母不得卡住修飾鍵。Terminal 運行 `sleep 30`，先選取可丟棄文字按 Ctrl+C 應複製且命令繼續；清除選取再按 Ctrl+C 應中斷。Ctrl+Shift+C 應明確中斷。另測選取資訊不可用時僅嘗試複製、查詢中切 App／暫停／撤銷來源不得送出舊中斷。IDE 內嵌 Terminal 使用整個 App 的 Windows 規則，另記錄其命令中斷綁定。遠端 Windows／VM 的 Ctrl+C／V 保持原 Ctrl，兩種後端各自驗收。手動App規則、快速切換、Pause應同步取消舊輸入法／AX／截圖任務。守護／切換熱鍵默認關閉；守護關閉時不修正系統輸入來源。

守護開啟後預設維持唯音繁體。用系統選單切成 ABC，應在設定延遲後回到唯音；切換本機 App、喚醒或重新啟動後仍應回到守護目標。用本 App 的 ABC 按鈕或唯音／ABC 快捷鍵選英文，應維持 ABC，並在重新啟動後保留此明確目標；本 App 選回唯音後，系統切英文應再次被修正。舊版記錄的「保留來源」不能當作明確英文選擇。

暫停偵測、Bridge Pause、Remote／VM／Game／Disabled、非作用中 session 與 Secure Input 期間不得自動切換；解除後應恢復目標，不把期間的 ABC 當作新目標。另測 Secure Input 期間按本 App 切換快捷鍵，離開密碼欄位後才完成切換。多個工具同時控制來源時，仍須觀察有界重試與衝突冷卻，確認沒有反覆切換迴圈。

## 8. 資源／封裝

一般模式、關閉診斷、設置窗口關閉，開機等待兩分鐘，Activity Monitor觀察5分鐘，目標平均0.0–0.1%，不能只看一張瞬間截圖。主App沒有固定250ms／1s閒置timer；按鍵、App/session通知和明確deadline會產生正常短暫活動。記錄同PID累計CPU增量、RSS與physical footprint；PID/version改變重新建baseline。自己的HID root process應無client後結束，共享Karabiner進程可能因其他軟件繼續運行。

分別從Git clone和無.git ZIP做Release arm64 build，核對Info版本／commit、資源allowlist、簽章與DMG App→Applications拖入；登入開關只改本App。停止／移除進階runtime保留共享Driver。沒有自制 MRU 或窗口遍歷切換器；AltTab 只使用 macOS native path。截圖縮圖只在成功截圖後短暫建立，未使用時沒有視窗與固定輪詢。

## 9. 規則預覽、遠端校準與文字擷取

總開關關閉時先開規則預覽，選 Terminal、IDE、Finder、瀏覽器、Remote／VM 與不同 Windows 鍵位置。核對 Ctrl+C／Ctrl+Shift+C、Ctrl+V、Alt+Tab、Shift+Delete 與截圖輸出，確認沒有實際按鍵輸出、沒有儲存模擬 Profile；最小 730×600 與放大視窗、鍵盤與 VoiceOver 操作都須可用。

從指定遠端來源送入按鍵後開始校準，切到本機 TextEdit 測一次 Ctrl+C。確認前設定不變；套用後重測並還原校準前手動設定。另一來源、一般打字、repeat、60 秒逾時、關閉校準頁、來源退出／重啟、Pause／Secure Input／權限撤銷不得套用結果。正常本機 App 切換應保持校準。分別記錄實際來源軟體與目標，不以 metadata 或 fixture 取代連線驗收。

用可丟棄的繁中／英文圖片框選文字，貼到測試文件，檢查數字、標點、換行、小字與多欄結果；一般截圖仍只複製圖片。沒有文字、取消、逾時、暫停、切換 Session 或撤銷螢幕錄製時原剪貼簿保持。辨識期間再次要求截圖不能啟動第二個工作；結束後再試。量測主 App 與單次 OCR worker 各自的 RSS／footprint，記錄冷／暖啟動與工作結束後記憶體，不要求辨識時 CPU 為零；確認不留命名 OCR 圖檔或文字日誌。
