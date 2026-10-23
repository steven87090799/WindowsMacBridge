# WindowsMacBridge 1.0.1（build 64）

這版改善兩台 Mac 透過 Apple「螢幕共享」／VNC 操作時的 Windows 快捷鍵。MacBook 在本機開啟 Fn／左 Ctrl 交換，一般 Mac 保持關閉；接收端 Bridge 會自動辨識 Apple 螢幕共享來源，將原始 Ctrl+C／V／Z 等 Windows 快捷鍵轉為 Mac 操作，已是 ⌘ 的快捷鍵保持原樣。兩台仍需各自安裝與授權。

同時修正輸入設定變更後，背景執行緒可能漏讀新設定而須切換總開關的問題；加入 Apple agent 的啟動與 session 恢復掃描。詳見[問題與修復記錄](ScreenSharingVNC-2026-10-24.md)。

本機 538 項 Swift 測試通過，包含 Apple VNC 身分、原始 Ctrl 複製／貼上／復原、Command 通過與遠端設定切換。自動化測試不能代替兩台 Mac 的實體 VNC 驗收。

下載 **WindowsMacBridge-1.0.1-macos-arm64.dmg** 或完整 App ZIP。先從選單列正常結束舊版，再將新版 App 放入「應用程式」。這是 Apple Silicon、macOS 14+ 的 ad-hoc 簽章版本，尚未 Apple 公證；更新後在每台 Mac 分別確認輔助功能、輸入監控與需要時的螢幕錄製授權。一般模式不需要安裝 Driver。

MacBook → Mac 的舊版現場曾驗證 Fn+C／V／Z；新版自動規則與 Mac → MacBook 的反向連線需依 [雙向步驟](../Resources/TwoMacAcceptance.md) 做實機驗收。未知來源第一次按鍵仍可能原樣通過，放開鍵後再測一次；長時間連續失敗時檢查接收端「遠端校準」中的 ScreensharingAgent 與權限狀態。
