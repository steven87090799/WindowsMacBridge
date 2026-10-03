# 2026-10-03 本機實測與監控交接

測試環境為 macOS 27.0、已安裝 WindowsMacBridge 0.6.0 (44)，一般 EventTap 模式。實機只有目前這台 Mac，未連線第二台 Mac 或 Windows Remote。以下分開記錄已觀察行為與未完成驗收；CI 不等同實體鍵盤或 Driver 驗收。

## 已確認錯誤與修復

10:23 快速切換功能時，原生 Tap registry 同時列出一個完整、啟用的攔截器及一個完整、已停用的舊攔截器；兩者 mask 均為 `1c00`。AX、listen、post 均為 true，舊版仍誤報未取得完整鍵盤事件。舊攔截器可能短暫留在 registry，不能用它否定新攔截器。

先加入以這組原生 metadata 重現的 regression test，確認修復前失敗。build 45 的程式碼忽略停用的舊 registry entries，同時要求呼叫端自己的 Mach port 有效且已啟用，所有正在運作的同程序鍵盤攔截器仍須具備完整 keyDown/keyUp/flagsChanged mask。其他 PID、只有停用攔截器或任何啟用但缺少事件的攔截器仍不能證明就緒。沒有新增輪詢、提權或放寬輸入來源判定。

目前監控的安裝版保持 build 44；修正版本的編譯／回歸證據與換版後的原生實测須分開記錄，不能把程式碼修復稱為已更新本機。

## 實測覆蓋

| 類別 | 已實際觀察 | 尚未驗收 |
|---|---|---|
| Windows 快捷鍵／持鍵 | 測試 TextEdit 中原生 ⌘C／⌘V 正常；自動化 Ctrl+C／V 未轉譯。核心開關停用／恢復狀態正確。 | 自動化帶有程式來源與目標路由，不能代替實體鍵盤；Ctrl 快捷鍵、重疊放開順序、兩把鍵盤、Secure Input 中斷仍未驗收。 |
| HID／EventTap／UC／Remote | 一般模式沒有自己的 Root HID Helper 服務；原生快照顯示三個完整、啟用的本 App EventTap。 | 雙 Mac 兩方向 UC、Windows Chrome Remote Desktop、混合裝置、兩端避免重複翻譯；未安裝／啟用進階後端來假裝驗收。 |
| Finder／視窗操作 | Finder 功能開關可以獨立切換並還原。 | Ctrl+X/V 移動、F2、焦點中的 Delete、永久刪除確認與 Alt+F4 未經實體事件驗收。未刪除使用者檔案。 |
| 截圖／圖片 | 授權後 10:13 的本 App 日誌記錄成功擷取並複製。關閉截圖後攔截器從三個降為一個，開啟後恢復三個。發現上述停用舊 Tap 的誤報。 | 無法由日誌判定那次使用哪個快捷鍵，亦未讀取使用者圖片或剪貼簿。四種 Windows 截圖、⌘⇧3/4、取消／舊工作與大圖整體峰值仍未實機驗收。 |
| 權限／安裝 | 三項必要原生權限皆已取得，登入項目已核准；正常退出重開後授權仍通過。build 44 DMG 有單一 App、Applications 連結與說明；完整複製到測試目錄後深層簽章通過，主程式與已安裝版相同。 | 此次不是清空環境的首次安裝。個人測試版未公證，首次 Gatekeeper 流程不等同已公證一般 App。進階 Driver 更新／重開機／共用回復未驗收。 |
| MacBook Fn／Ctrl | 此台未開啟 MacBook 交換模式。 | 需要 MacBook 內建鍵盤，外接不受影響、UC 傳送與 crash 還原尚未驗收。 |
| 唯音／App 模式 | App 按鈕切換 ABC、切回唯音成功並保留手動選擇；原本開關与規則均還原。 | 組字／選字、切換熱鍵的實體觸發、Terminal 中斷、快速切換與暫停交互作用未驗收。 |
| 資源／封裝 | 功能操作階段同 PID 五分鐘 CPU 平均約 0.38%，初次 footprint 41.9 MiB；原生活動監視器主 App GPU 瞬間為 0.0%、累積 GPU 時間 0.00。已關閉設定視窗，開始獨立閒置取樣。PR #11 的兩項必要 CI 通過。 | UI 操作數據不是 0.0–0.1% 閒置目標驗收。GPU 瞬間不證明峰值為零。截圖程序／WindowServer／剪貼簿整體峰值與 build 45 原生換版仍待測。 |

## 持續監控

已將既有監控恢復為每半小時一次。只在確認的 CPU／記憶體異常、新崩潰或持續功能錯誤時通知；不同 PID／版本不共用 CPU 基線，休眠或 Codex 未運作造成空窗需保留。CPU、RSS 與 physical footprint 分別記錄，系統 CPU／swap 不能歸因 App。

本輪閒置 sampler 每五分鐘取得累計 CPU／RSS，每半小時取得 footprint 與系統 totals，最多三小時；之後 heartbeat 繼續低負載快照。Finder extension 由 macOS 保留時單獨量測，它的 `directoryURLs` 已為空，存在進程不表示全磁碟監控。共享 Karabiner 服務保留，不停止其他程式的依賴。

GPU 只有原生工具提供此 App 的數值時才記錄；活動監視器未開啟或搜尋條件已變更時標示不可取得，不啟動常駐 profiler，不把全系統 GPU 當本 App 使用率。監控不讀輸入文字、剪貼簿、文件內容，也不替使用者變更授權。
