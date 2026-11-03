# Mac mini 與 MacBook：雙向通用控制與螢幕共享驗收

2026-10-24 已有兩台 Mac 的部分實測證據，見下方「1.0.1 現場結果」。其餘步驟仍須由使用者在實體裝置操作；程式測試／CI 不替代這些格子。

1. 兩台都將同版 App 拖到應用程式，使用一般模式，核准各自輔助功能。
2. Mac mini 的外接鍵盤保持固定，MacBook 使用內建鍵盤。僅 MacBook 開啟「MacBook 鍵盤模式」，先確認 Fn+C／V 等於 Ctrl+C／V，原左 Ctrl 可作 Fn。Mac mini 不開交換。
3. 兩台先各自在 TextEdit 做本機 Ctrl+A/C/V/Z，核對外接鍵盤未交換。Terminal 與 IDE 測 Ctrl+C/V/A/X；Terminal 用 Ctrl+Shift+C 中斷命令。
4. 系統設定 → 顯示器 → 進階 → 通用控制，按 Apple 提供的連線條件使用同一 Apple Account；游標跨邊緣後先放開所有鍵，再在目的端 TextEdit 複製貼上。
5. MacBook→Mac mini：來源端開 Terminal，目的端開 TextEdit，Fn+C 應在目的端複製，來源Terminal不能中斷。再在 Finder 用可丟棄檔案測 Ctrl+X／V，來源 Finder 不得操作。
6. Mac mini→MacBook：外接 Ctrl+C 應在目的端複製，MacBook 的 Fn 交換不能套到外接／UC 服務上。
7. 兩方向都測：按 Ctrl+C 後繼續按住 Ctrl 再 Tab、Ctrl+Shift 重疊、先放字母／先放 Ctrl、持鍵跨邊緣、切 App、Pause、斷線／重新連線、休眠喚醒。放開所有鍵後應恢復，沒有殘留 Command／Option。
8. Shift+Option+S（Win+Shift+S）／PrintScreen、⌘⇧3／⌘⇧4 截圖後直接 Ctrl+V；取消不改剪貼簿，Pause 後舊框選不得寫入新 session。

兩方向另外測 Option+E／L、啟用的 Option+R／I／Tab，以及 Command+Tab／F4（Windows Alt）。接收端遠端語意為「自動」時，已是 Command 的 Mac 快捷鍵保持原樣；確定需要 Windows Alt 動作時使用該來源的「原始 Windows 按鍵」模式。首次與重新連線後各測一次。

每格記錄兩臺 macOS／App 版本、方向、鍵盤、來源／目的 App、成功與失敗。一般模式 EventTap 的來源／目的 metadata 可能被 UC 隱藏；若某一格失敗，保留具體組合再評估進階模式，不把整體標成「100% 支援」。進階需另外測硬件接管與釋放，不要在第二臺安裝舊版 helper。

## 1.0.1 現場結果（2026-10-24）

| 路徑 | 實體鍵盤與目的端 | 結果 |
| --- | --- | --- |
| Mac → MacBook 螢幕共享 | Mac 外接 Ctrl+C／V／Z → MacBook 文字編輯 | 使用者回報三者成功 |
| Mac → MacBook 通用控制 | Mac 外接 Ctrl+C／V → MacBook 文字編輯 | 使用者回報成功 |
| MacBook 本機 | 內建 Fn+C／V → MacBook 文字編輯 | 使用者回報成功；現有 Karabiner 未阻擋這次測試 |
| MacBook → Mac 通用控制 | MacBook 內建 Fn+C／V → Mac 文字編輯 | 使用者回報成功；Mac 的測試文件確實出現兩次新文字 |

Mac 文件末尾的額外 `v` 由使用者手動輸入，不能判定為第一次 Fn+V 失效。MacBook → Mac 螢幕共享的先前實測另見 [ScreenSharingVNC-2026-10-24.md](../Docs/ScreenSharingVNC-2026-10-24.md)。尚未完成重新連線後第一下、移除 Karabiner 後、更多快捷鍵與 App 的驗收。

## 1.0.3 build 68 多選與快捷鍵補充（尚待實機驗收）

1. 本機 Finder 使用三個可丟棄檔案：按住 Ctrl 逐一左鍵點選第一與第三個，再點第一個取消，核對選取數量。測 Ctrl＋Shift、先放 Ctrl 再放左鍵、拖曳後放鍵、一般右鍵，以及暫停後恢復原生 Ctrl＋點擊。
2. Windows → Google 遠端桌面 → 接收端 Mac：在 Mac 安裝 build 68，Windows 用實體 Ctrl 重複上述操作；遠端校準保留 Google host「自動」。核對初次、斷線重連後第一下與第二下。本機測試或合成事件不等於這條遠端路徑已通過。
3. Apple 螢幕共享與通用控制另行測兩方向；Mac mini 用外接 Ctrl，MacBook 僅在啟用內建 Fn／Ctrl 交換時用 Fn。記錄版本、方向、實體按鍵與結果，不能由 Google 路徑推論其餘路徑。
4. Finder 用可丟棄檔案測 Ctrl＋拖曳複製與 Ctrl＋Shift＋拖曳建立替身，核對來源仍存在、目的內容正確；不要只看游標。測先放 Ctrl 再放滑鼠，以及暫停／失焦後下一次普通點擊。
5. TextEdit 測 Ctrl+B／I／U、Ctrl+Shift+V、Ctrl+Insert／Shift+Insert、Ctrl+上下鍵與選取。Finder 測 Ctrl+F／T、Alt+Enter；Chrome／Firefox／Safari 分別測 Ctrl+H／J、F3／F5，以及網頁和網址／文字欄位中的 Home／End。離開文字欄位後不得把 Home／End 送成瀏覽歷史。
6. Google 自動模式測 Alt+F4／Alt+PrintScreen；原生 Command+C／D／Shift+S 保持原樣。需要完整 Windows Alt 動作時單獨測「原始 Windows 按鍵」；不把兩種設定的結果混在一起。

## Apple 螢幕共享／VNC 鍵盤驗收

1. 兩台各安裝同版 Bridge 並各自核准輔助功能與輸入監控；MacBook 開啟「MacBook 鍵盤模式」，一般 Mac 保持關閉。接收端「Windows 模式總開關」保持開啟，遠端來源保留「自動」。
2. MacBook 控制一般 Mac：在接收端 TextEdit 選取新文字，用 MacBook Fn+C、Fn+V、Fn+Z 各測一次。接收端遠端校準頁應出現 Apple ScreensharingAgent。
3. 一般 Mac 控制 MacBook：在接收端 TextEdit 選取新文字，用一般 Mac 鍵盤 Ctrl+C、Ctrl+V、Ctrl+Z 各測一次。MacBook 的 Fn／Ctrl 交換不應改變傳入的遠端按鍵。
4. 兩方向都重新連線再測；記錄第一下與第二下是否一致。未知來源首次按鍵可能原樣通過，不能把單向成功視為雙向驗收。若持續失敗，檢查接收端來源、權限、Secure Input 與目前 App 規則，再決定是否校準；不要以共享剪貼簿開關代替同一台 Mac 上的快捷鍵測試。
