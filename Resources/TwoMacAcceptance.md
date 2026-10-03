# Mac mini 與 MacBook：雙向通用控制驗收

目前没有第二臺 Mac 的實測證據，以下由使用者操作；程式測試／CI 不替代這些格子。

1. 两台都将同版 App 拖到應用程式，使用一般模式，核准各自輔助功能。
2. Mac mini 的外接鍵盤保持固定，MacBook 使用內建鍵盤。仅 MacBook 开啟「MacBook 鍵盤模式」，先確認 Fn+C／V 等於 Ctrl+C／V，原左 Ctrl 可作 Fn。Mac mini 不開交換。
3. 两台先各自在 TextEdit 做本機 Ctrl+A/C/V/Z，核對外接鍵盤未交換。保留 Terminal Ctrl+C 中斷功能。
4. 系統設定 → 顯示器 → 進階 → 通用控制，按 Apple 提供的連線条件使用同一 Apple Account；游標跨邊緣後先放開所有键，再在目的端 TextEdit 複製貼上。
5. MacBook→Mac mini：來源端開 Terminal，目的端開 TextEdit，Fn+C 应在目的端复制，来源Terminal不能中斷。再在 Finder 用可丟棄檔案測 Ctrl+X／V，來源 Finder 不得操作。
6. Mac mini→MacBook：外接 Ctrl+C 应在目的端复制，MacBook 的 Fn 交换不能套到外接／UC 服务上。
7. 兩方向都測：按 Ctrl+C 后繼續按住 Ctrl 再 Tab、Ctrl+Shift 重疊、先放字母／先放 Ctrl、持鍵跨邊缘、切 App、Pause、断線／重新連線、休眠喚醒。放开所有键后应恢复，没有残留 Command／Option。
8. Win+Shift+S／PrintScreen、⌘⇧3／⌘⇧4 截图后直接 Ctrl+V；取消不改剪贴簿，Pause 后旧框选不得写入新 session。

每格記錄兩臺 macOS／App 版本、方向、鍵盤、來源／目的 App、成功與失敗。一般模式 EventTap 的來源／目的 metadata 可能被 UC 隱藏；若某一格失敗，保留具體組合再评估进阶模式，不把整体标成「100% 支援」。进阶需另外测硬件接管与释放，不要在第二臺安装旧版 helper。
