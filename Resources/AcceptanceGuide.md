# WindowsMacBridge：人工驗收指南

程序碼回歸／CI、Release 封裝、Installed GUI 授權、實體鍵盤、跨機與資源量測是不同證據。以下尚未實機驗收。用可丟棄文字與檔案，勿在重要文件做故障測試。

## 最短開始

DMG 拖入 Applications → 一般模式 → 權限頁逐項核准輔助功能與輸入監控 → 原生確認綠燈 → TextEdit Ctrl+C/V。螢幕錄製單獨列出，登入時啟動為選用；一般模式不應要求 Root／Driver，也不應自動註冊登入。首次截圖可能要求螢幕錄製；核准後重開 App 再試。不用安裝 Finder 擴充。

## 1. 快捷鍵與持鍵

TextEdit、Safari 各測 Ctrl+A/C/X/V/Z/Y/F/S/P、Ctrl+Tab、Ctrl+Shift+Tab、Ctrl+T/W／Shift+T、Ctrl+Arrow／Shift+Arrow、Home/End/Delete。先複製後按住 Ctrl 再 Tab，確認仍是分頁切換，沒有殘留 Command。左右 Ctrl／Shift／Alt 重疊，字母先放／修飾鍵先放各測一次。按住 Ctrl 在兩個普通 App 來回，重復 Ctrl+C；進入 Remote、Pause、Secure Input、session鎖定後放開鍵，回來新快捷鍵恢復。不要關閉系統的真正安全輸入。

一般模式無法可靠按鍵盤 ID 分流；若另接第二把測試，兩把同按相同按鍵時記錄 aggregate flags 的限制。使用者實際環境是 Mac mini 外接＋MacBook 內建，雙機按下一節。

## 2. UC／Remote／HID 分流

按 [TwoMacAcceptance.md](TwoMacAcceptance.md) 測兩方向，特別是來源 Terminal→目的 TextEdit 的 Ctrl+C、兩端都裝 App、持鍵跨屏。Windows→Google Chrome Remote Desktop Host→Mac mini：在 Mac TextEdit 試 Ctrl+C/V/X/Z/A/S，已是 Command 不再翻譯。Mac→Windows viewer／VM：同樣組合應保持 Windows Ctrl，Alt+Tab 按客戶端轉發設置處理。隱藏 PID、未知復合 HID、混合 Native Mac 裝置與 Remote 手動 profile 各自記錄，未經操作保持「未驗收」。

## 3. Finder 與窗口

兩個測試文件：Ctrl+X→進新目錄→Ctrl+V，應該移動一次，clipboard改變／超過5分鐘不能繼續舊move。F2改名、Delete垃圾桶。文件名文字編輯中的Delete應刪字，未知焦點不盲刪。Shift+Delete確認取消不刪除；確認刪除只用可丟棄文件。Alt+F4只關當前窗口，保留未儲存對話，不退出整個App。一般App亮度鍵不能變Enter。打開多目錄檢查Finder延遲；沒有全磁碟 FinderSync 監控，但流暢度仍須實測。

## 4. 截圖與記憶體

Win+Shift+S／PrintScreen框選、Alt+PrintScreen當前窗口、Win+PrintScreen全屏存檔，完成後直接 Ctrl+V／Cmd+V。CmdShift3全屏、CmdShift4選區也複製；暫停或關閉功能後恢復系統原生行為。Esc取消保持原clipboard。框選尚未結束→Pause／換backend／鎖屏／切App／關功能再開，舊結果不得寫入。核准／撤銷 ScreenCapture 後結果不得顯示偽成功；磁碟／程序／解碼／編碼失敗各有錯誤。

圖片預算覆蓋PNG／TIFF／PDF、PDF嵌圖與inline image，壓縮文件小不表示可無限解碼。記錄5K／4K多屏截圖時 **App＋screencapture＋WindowServer＋clipboard** 的峰值，分開 RSS 與 footprint；現有預算不是整體峰值保證。不要用自動化讀取使用者當前clipboard或屏幕作為測試素材。

## 5. 進階權限與Driver／安裝

只有明確勾進階才安裝／連XPC。逐項授權輸入監控、官方Driver；原生IOHID／driver核對才能綠燈。首裝、與Karabiner共用、更新中斷、timeout、需要用戶批准／重開機、回滾須實機測，fixture通過不算硬件驗收。切回一般應關閉自己的runtime，不停止／刪除其他軟件的共享Driver。權限只改本App，不重設全部TCC；ad-hoc更新重新授權屬於現有簽章限制。

## 6. MacBook 原生映射

僅builtIn=true的本機Apple鍵盤交換Fn／左Ctrl；Mac mini、USB／Bluetooth、UC／virtual不交換。正常退出還原；與他人工具Fn／Ctrl衝突要顯示問題且不覆蓋其他pair。強制退出後下次啓動／登入應處理journal；重開機服務映射清除。睡眠／喚醒、服務重建、持鍵切換與restorePending都實測，不能用property setter返回true就判定成功。

## 7. 輸入法與App模式

ABC與唯音各測組字、選字、Enter／Backspace／Shift／CapsLock，再測試複製。終端運行 `sleep 30` 後 Ctrl+C 應中斷，IDE內嵌Terminal同樣。手動App規則、快速切換、Pause應同步取消舊輸入法／AX／截圖任務。守護／切換熱鍵默認關閉；守護關閉時不修正系統輸入來源。

守護開啟後預設維持唯音繁體。用系統選單切成 ABC，應在設定延遲後回到唯音；切換本機 App、喚醒或重新啟動後仍應回到守護目標。用本 App 的 ABC 按鈕或唯音／ABC 快捷鍵選英文，應維持 ABC，並在重新啟動後保留此明確目標；本 App 選回唯音後，系統切英文應再次被修正。舊版記錄的「保留來源」不能當作明確英文選擇。

暫停偵測、Bridge Pause、Remote／VM／Game／Disabled、非作用中 session 與 Secure Input 期間不得自動切換；解除後應恢復目標，不把期間的 ABC 當作新目標。另測 Secure Input 期間按本 App 切換快捷鍵，離開密碼欄位後才完成切換。多個工具同時控制來源時，仍須觀察有界重試與衝突冷卻，確認沒有反覆切換迴圈。

## 8. 資源／封裝

一般模式、關閉診斷、設置窗口關閉，開機等待兩分鐘，Activity Monitor觀察5分鐘，目標平均0.0–0.1%，不能只看一張瞬間截圖。主App沒有固定250ms／1s閒置timer；按鍵、App/session通知和明確deadline會產生正常短暫活動。記錄同PID累計CPU增量、RSS與physical footprint；PID/version改變重新建baseline。自己的HID root process應無client後結束，共享Karabiner進程可能因其他軟件繼續運行。

分別從Git clone和無.git ZIP做Release arm64 build，核對Info版本／commit、資源allowlist、簽章與DMG App→Applications拖入；登入開關只改本App。停止／移除進階runtime保留共享Driver。沒有自制MRU、thumbnail、窗口遍歷切換器；AltTab只使用macOS native path。
