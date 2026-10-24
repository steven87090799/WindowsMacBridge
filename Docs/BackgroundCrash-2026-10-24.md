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

## 1.0.2（build 65）的處理

- 共用 `RunningApplicationSnapshot` 解析前景與接收端 App；略過 PID ≤ 0 或已結束的物件，在讀取 metadata 後再確認未結束。
- 同一有效 PID 的重複項目以後一筆有效 context 更新，不再使用會因重複 key 當機的初始化方法。
- 每個物件只讀取一次 PID，同時用於字典 key 與 context，避免讀取兩次所得身分不一致。
- 每次完整刷新建立新清單，移除已離開的 App；按需解析接收端時也移除無法解析的舊 context。無效前景使用原有停用規則，不沿用另一個 App 的特殊操作。
- 保留既有的事件通知機制，不增加閒置輪詢、登入註冊或常駐監督程序。這次修正防止已確認的當機路徑，並非對任意其他當機提供自動重啟。

## 回歸驗證

新增 8 項測試涵蓋這次的兩筆 -1 清單、其他非正 PID、已結束物件、讀取 metadata 時結束、有效 PID 重複、PID 讀取一致性、多次生命週期刷新、原有 App 規則及覆寫、缺失 registry 時停用，以及實際 AppKit adapter。測試也驗證保留的 Terminal recipient 能繼續提供正確的目的端規則。

完整測試與封裝結果記錄於 [1.0.2 更新說明](ReleaseNotes-1.0.2.md)。長時間睡眠／喚醒、其他 Mac 與各種硬體仍需實機觀察；合成清單可重現這次的輸入條件，不能取代所有實機情境。
