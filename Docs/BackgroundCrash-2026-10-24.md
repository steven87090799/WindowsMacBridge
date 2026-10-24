# 2026-10-24 背景程式當機：原因與修正

## 現場證據

安裝版本為 WindowsMacBridge **1.0.1（build 64）**，執行檔 UUID 與 macOS 當機報告一致。以下時間均為台北時間（UTC+08:00）：

| 時間 | 事件 |
|---|---|
| 10/24 01:08:55 | 本次舊程序啟動 |
| 10/24 11:46:07 | 睡眠後恢復，輸入法與鍵盤映射的紀錄顯示程式仍在工作 |
| 10/24 11:47:16 | Swift runtime 記錄 `Fatal error: Duplicate values for key: '-1'`，程序以 SIGTRAP 結束 |
| 10/24 12:19:50 | 使用者手動開啟 App，建立新程序 |

當時系統的登入項目資料顯示 WindowsMacBridge 為 enabled／allowed。因此這次的背景停止可由確定的當機事件解釋；登入開關不能修復執行中的程式缺陷。

當機堆疊：`_assertionFailure` → `_NativeDictionary.merge(trappingOnDuplicates:)` → `BridgeController.refreshRecipientContexts()` → `refreshApplication()` → NSWorkspace 通知處理。原始私人系統報告與完整日誌不放入公開 repository。

## 為什麼會發生

程式為了判斷哪個本機 App 接收快捷鍵，會在應用程式啟動、切換、結束和喚醒等通知後，重新整理 NSWorkspace 的應用程式清單。舊版以 `Dictionary(uniqueKeysWithValues:)` 建立「PID → App 規則」對照表，假設每一筆 PID 都唯一。

Apple 的 `NSRunningApplication.h` 說明：不是每個應用程式物件都有 PID；沒有 PID 時 `processIdentifier` 回傳 **-1**，且 App 結束後物件仍可能存在。多個沒有 PID 的物件便會給出相同的 -1。Swift 的這個字典初始化方法要求所有 key 唯一，遇到重複 key 會直接觸發 runtime error，整個選單列程式因此退出。

這次系統日誌確定記錄重複 key 為 -1。當機發生在喚醒後約一分鐘的應用程式清單刷新；沒有保留當時的完整清單，不能聲稱是哪一個特定 App 造成，也不能把「喚醒」當作此缺陷的唯一觸發條件。

參考：[Apple processIdentifier](https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier)、[Swift Dictionary 初始化](https://developer.apple.com/documentation/swift/dictionary/init(uniquekeyswithvalues:))。

## 1.0.2（build 66）的處理

- 共用 `RunningApplicationSnapshot` 解析前景與接收端 App；略過 PID ≤ 0 或已結束的物件，在讀取 metadata 後再確認未結束。
- 同一有效 PID 的重複項目以後一筆有效 context 更新，不再使用會因重複 key 當機的初始化方法。
- 每個物件只讀取一次 PID，同時用於字典 key 與 context，避免讀取兩次所得身分不一致。
- 每次完整刷新建立新清單，移除已離開的 App；按需解析接收端時也移除無法解析的舊 context。無效前景使用原有停用規則，不沿用另一個 App 的特殊操作。
- 保留既有的事件通知機制，不增加閒置輪詢或登入註冊。

## 非預期停止後的恢復與告知

使用者進一步要求：即使將來有其他當機，也不應無聲消失。正式交付的 1.0.2 build 66 因此加入獨立的輕量恢復程序，與上述根因修復一起封裝。

- 安裝位置的主 App 啟動時開啟內含的 `WindowsMacBridgeRecovery`。它阻塞等待專用 pipe；沒有心跳、固定閒置 timer、Root helper 或另外註冊的登入服務。
- 正常「結束」、權限重新啟動或更新的正常退出，先送出停止訊號，恢復程序一同結束，不自行重開。
- 主 App 非預期停止使 pipe 關閉時，延遲 1／3／10 秒嘗試重開。本輪五分鐘內最多三次；超過次數或無法確認重新啟動，就停止嘗試並顯示系統提示。
- 新 App 必須成功建立自己的恢復程序，才寫回一次性確認。單純 `open` 回傳成功不算恢復成功；確認最多等 15 秒，使用目錄事件而非輪詢。延遲期間使用者手動開啟 App 時，既有的單實例鎖優先，舊恢復程序不再重開另一份。
- 自動恢復後 App 顯示「已自動重新啟動」，一般設定也顯示自動恢復狀態。恢復程序本身意外停止時，主 App 會明確提示保護未就緒。
- 私人恢復紀錄位於 `~/Library/Application Support/WindowsMacBridge/Recovery/Recovery.log`，限制約 64 KiB；不記錄按鍵內容或剪貼簿。登入時啟動仍由使用者原本的開關控制。

## 回歸驗證

新增 8 項測試涵蓋這次的兩筆 -1 清單、其他非正 PID、已結束物件、讀取 metadata 時結束、有效 PID 重複、PID 讀取一致性、多次生命週期刷新、原有 App 規則及覆寫、缺失 registry 時停用，以及實際 AppKit adapter。測試也驗證保留的 Terminal recipient 能繼續提供正確的目的端規則。

完整測試與封裝結果記錄於 [1.0.2 更新說明](ReleaseNotes-1.0.2.md)。長時間睡眠／喚醒、其他 Mac 與各種硬體仍需實機觀察；合成清單可重現這次的輸入條件，不能取代所有實機情境。
