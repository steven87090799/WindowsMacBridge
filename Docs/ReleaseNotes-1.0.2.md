# WindowsMacBridge 1.0.2（build 65）

修正 WindowsMacBridge 可能在背景突然退出、必須手動重開的問題。1.0.1 在重新整理應用程式清單時，若系統回傳多筆沒有程序編號的項目（PID -1），會因字典 key 重複而整個當機。1.0.2 略過無效與已結束項目，安全更新重複的有效 PID，並保留快捷鍵接收端的正確身分。詳見[當機證據、原因與修正](BackgroundCrash-2026-10-24.md)。

這版保留 1.0.1 的 Apple 螢幕共享／VNC、通用控制與 MacBook Fn／左 Ctrl 功能；登入時啟動仍沿用使用者自己的選擇。

## 下載與更新

在 [v1.0.2 發行頁](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.2) 下載 **WindowsMacBridge-1.0.2-macos-arm64.dmg** 或完整 App ZIP。先從選單列正常結束舊版，再將新版 App 拖入「應用程式」並開啟。

適用 **Apple Silicon（M 系列）、macOS 14 以上**。App 使用 ad-hoc 簽章，尚未 Apple 公證。首次跨機開啟或更新後，macOS 可能要求額外確認與重新授權；在每台 Mac 分別核准輔助功能、輸入監控與需要時的螢幕錄製。一般模式不需要另裝 Driver、Homebrew 或 Xcode。不要將別台電腦的鍵盤還原紀錄或個人權限資料搬過來。

希望登入後自動執行，可在設定 → 一般開啟「開機自動啟動」。這個選項負責登入啟動；本次當機修正由新版程式碼處理。

## 驗證範圍

本機 Debug／Release 各 **546 項 Swift 測試通過**，包含新增的 8 項當機與生命週期回歸測試，以及隔離執行的記憶體回歸。發行附件 `WindowsMacBridge-build-info.json` 記錄實際建置版本、來源 commit、封裝驗證與檔案雜湊；GitHub CI 狀態以對應提交的 Actions 結果為準。

這次未重新進行兩台 Mac 的實體鍵盤或進階 Driver 安裝驗收；1.0.1 的既有觀察保留於 [TwoMacAcceptance.md](../Resources/TwoMacAcceptance.md)，不能當成本版所有硬體已重新驗收。
