# WindowsMacBridge 1.0.2（build 66）

修正 WindowsMacBridge 可能在背景突然退出、必須手動重開的問題。1.0.1 在重新整理應用程式清單時，若系統回傳多筆沒有程序編號的項目（PID -1），會因字典 key 重複而整個當機。1.0.2 略過無效與已結束項目，安全更新重複的有效 PID，並保留快捷鍵接收端的正確身分。詳見[當機證據、原因與修正](BackgroundCrash-2026-10-24.md)。

這版保留 1.0.1 的 Apple 螢幕共享／VNC、通用控制與 MacBook Fn／左 Ctrl 功能；登入時啟動仍沿用使用者自己的選擇。

也加入異常停止後的自動恢復與提示：意外停止時重新開啟，成功後顯示恢復訊息；主動按「結束」會正常關閉。本輪五分鐘內最多恢復三次，連續失敗或無法確認啟動時停止嘗試並通知使用者。一般設定顯示保護狀態，恢復程序本身停止也會告知。平常以事件等待，不增加心跳輪詢。

## 下載與更新

在 [v1.0.2 發行頁](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.2) 下載 **WindowsMacBridge-1.0.2-macos-arm64.dmg** 或完整 App ZIP。先從選單列正常結束舊版，再將新版 App 拖入「應用程式」並開啟。

適用 **Apple Silicon（M 系列）、macOS 14 以上**。App 使用 ad-hoc 簽章，尚未 Apple 公證。首次跨機開啟或更新後，macOS 可能要求額外確認與重新授權；在每台 Mac 分別核准輔助功能、輸入監控與需要時的螢幕錄製。一般模式不需要另裝 Driver、Homebrew 或 Xcode。不要將別台電腦的鍵盤還原紀錄或個人權限資料搬過來。

希望登入後自動執行，可在設定 → 一般開啟「開機自動啟動」。這個選項負責登入啟動；本次當機修正由新版程式碼處理。

## 驗證範圍

本機 Debug／Release 各 **551 項 Swift 測試通過**，含 8 項應用程式清單回歸與 5 項恢復交接驗證。另有 **13 項恢復程序測試通過**，涵蓋正常結束、異常停止、重開確認、次數限制、啟動卡住與失敗提示。發行檔驗證記錄在附件 `WindowsMacBridge-build-info.json`；GitHub CI 狀態以對應提交的 Actions 結果為準。

這次未重新進行兩台 Mac 的實體鍵盤或進階 Driver 安裝驗收；1.0.1 的既有觀察保留於 [TwoMacAcceptance.md](../Resources/TwoMacAcceptance.md)，不能當成本版所有硬體已重新驗收。
