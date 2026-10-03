# Mac mini 與 MacBook：雙向通用控制驗收

目前沒有第二臺 Mac 的實測證據，以下由使用者操作；程式測試／CI 不替代這些格子。

1. 兩台都將同版 App 拖到應用程式，使用一般模式，核准各自輔助功能。
2. Mac mini 的外接鍵盤保持固定，MacBook 使用內建鍵盤。僅 MacBook 開啟「MacBook 鍵盤模式」，先確認 Fn+C／V 等於 Ctrl+C／V，原左 Ctrl 可作 Fn。Mac mini 不開交換。
3. 兩台先各自在 TextEdit 做本機 Ctrl+A/C/V/Z，核對外接鍵盤未交換。保留 Terminal Ctrl+C 中斷功能。
4. 系統設定 → 顯示器 → 進階 → 通用控制，按 Apple 提供的連線條件使用同一 Apple Account；游標跨邊緣後先放開所有鍵，再在目的端 TextEdit 複製貼上。
5. MacBook→Mac mini：來源端開 Terminal，目的端開 TextEdit，Fn+C 應在目的端複製，來源Terminal不能中斷。再在 Finder 用可丟棄檔案測 Ctrl+X／V，來源 Finder 不得操作。
6. Mac mini→MacBook：外接 Ctrl+C 應在目的端複製，MacBook 的 Fn 交換不能套到外接／UC 服務上。
7. 兩方向都測：按 Ctrl+C 後繼續按住 Ctrl 再 Tab、Ctrl+Shift 重疊、先放字母／先放 Ctrl、持鍵跨邊緣、切 App、Pause、斷線／重新連線、休眠喚醒。放開所有鍵後應恢復，沒有殘留 Command／Option。
8. Win+Shift+S／PrintScreen、⌘⇧3／⌘⇧4 截圖後直接 Ctrl+V；取消不改剪貼簿，Pause 後舊框選不得寫入新 session。

每格記錄兩臺 macOS／App 版本、方向、鍵盤、來源／目的 App、成功與失敗。一般模式 EventTap 的來源／目的 metadata 可能被 UC 隱藏；若某一格失敗，保留具體組合再評估進階模式，不把整體標成「100% 支援」。進階需另外測硬件接管與釋放，不要在第二臺安裝舊版 helper。
