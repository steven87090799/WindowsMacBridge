# 兩台 Mac 的安裝、使用與驗收（0.5.17 / build 36）

目前狀態：2026-10-02 reviewer 修正納入 0.5.17 / build 36（preview.8）安裝候選版。依使用者後續安裝要求進行必要建置與封裝，只執行權限及事件遮罩的針對性檢查，沒有執行完整測試套件；仍須依以下步驟實機驗收。舊 preview.1 / build 29 不含 reviewer 修正。詳見 Docs/ReviewerAudit-2026-10-02.md。

以下實體操作尚未完成。MacBook 已開通用控制、尚未安裝 Bridge，可以照此順序加入。兩台都用 Apple Silicon / macOS 14 以上。不要把一台 Mac 的測試結果當成另一台也通過。

## 1. 先準備兩台，不急著跨機測

稱目前這台為 A，MacBook 為 B。先確認不開 Bridge 時，A 的滑鼠能移到 B，鍵盤能在 B 的 TextEdit 打字，再反向確認 B → A。這一步只驗證 Apple 通用控制。

將同一個 `WindowsMacBridge-0.5.17-preview.8-app-macos-arm64.zip` 傳到兩台並解壓縮。此 ZIP 解壓後只有 WindowsMacBridge.app，背景元件已收在 App 內。兩台都使用此單一 App 版。

1. A：從 Bridge 選單正常結束旧版；B 尚未安裝可直接下一步。先放開所有按鍵。
2. 各自在解壓縮資料夾開啟 App，程式自動安裝，依系統要求完成管理員驗證。所有背景元件已內含，不用加入或選取程式。遇到未知或其他程式共用的不相容 Driver 時會保留現狀並顯示安裝失敗；不手動刪除共用 Driver。
3. 安裝完成會重新開啟權限清單。依序按各項「開啟設定」、在 macOS 核准、回到 App 確認綠燈。若系统要求重新開機或重新開啟 App，請依提示完成。安裝取消不自動反覆重試。
4. 從各自的 `/Applications/WindowsMacBridge.app` 開啟設定，確認 **0.5.17（35）**。在第一項「開啟設定」完成鍵盤控制；App 必須實際顯示 Accessibility 與事件輸出都取得，不能只看系統同名開關。WindowsMacBridge 主 App 也需輸入監控；HID helper 需自己的輸入監控，Win+Shift+S 另需螢幕錄製。八項設定均在權限頁平鋪；第 8 項由程式申請目前截圖資料夾存取，不需選取路徑。
5. 安裝完成已準備 Windows Experience、**裝置 HID**、**所有支援的鍵盤**；保留手動 App／來源偏好。MacBook 偵測到內建 Apple 鍵盤時啟用 Fn／Ctrl 交換，Mac mini 不會自動交換外接鍵盤。確認 helper／Driver Ready，來源端的實體鍵盤有被接管。目的端 UC 事件本身不要求被 seize。
6. 若 Karabiner 或其他改鍵程式也在改同一把鍵盤，先由你選擇停用那把鍵盤的重疊規則，再測 Bridge；保留它的共用 Driver。不要同時改多個設定排查。

每台先在自己的 TextEdit 測 Ctrl+A、C、V、Z。若這裡不正常，先處理授權／Ready，還不用測通用控制。

## 2. 兩台平常怎麼用

滑鼠游標在哪一台、哪個文字欄位取得焦點，就在那台執行 Ctrl+C／V 等動作。来源端保留原始 App 敏感按鍵，目的端依自己的 App 決定語意。兩端都安裝同版是此候選版的跨機測試前提。

- 目的端是 TextEdit：Ctrl+C 應複製選取文字，Ctrl+V 貼上。
- 目的端是 Terminal：Ctrl+C 仍是 Terminal 的原生 Control+C，不能強制改成複製。
- `⌘⇧3`／`⌘⇧4`：保留 macOS 截圖操作，系統完成存檔後自動複製；直接到另一個 App 按 ⌘V（Bridge 一般文字 Profile 也可 Ctrl+V）。不用點開縮圖。浮動縮圖可能延後存檔數秒；Win+Shift+S 也使用此原生存檔與自動複製流程。
- Native 截圖使用 macOS 選定的本機存檔目錄。選「剪貼簿」時由 macOS 自己複製；選 Preview／Mail 等不產生該目錄新檔的目的地，不在檔案自動複製範圍。更改存檔目錄後重新開關 Bridge 截圖功能。

通用剪貼簿可能自行同步兩台內容，所以「兩台剪貼簿相同」不能證明在來源端誤執行，也不能证明沒有誤執行。看動作發生的視窗、文字和截圖是哪台，比只看剪貼簿可靠。

## 3. 依序驗收，每一列反向再測一次

只使用可丟棄的 TextEdit 文件與測試資料夾。每列開始前放開所有按鍵。

| 測試 | 操作 | 通過條件 |
|---|---|---|
| 基本跨機 | A 鍵盤透過 UC 控制 B，B 選取 `B-target`，Ctrl+C 再 Ctrl+V | B 貼上一次選取文字；A 前景文字／視窗不被操作 |
| 来源 Terminal | A 留在 Terminal，游標移到 B 的 TextEdit，選取測試文字後 Ctrl+C／V | 依 B 的文字 App 複製貼上；不能因 A 是 Terminal 而不翻譯 |
| 目的 Terminal | A 在 TextEdit，控制 B Terminal；B 執行 `sleep 30` 後 Ctrl+C | B 的 sleep 被中斷，沒有把 Ctrl+C 變複製；A 文字不動 |
| 兩端避免重複 | 兩端 Bridge 都開，B TextEdit 分兩次輸入文字（每次完成後停頓）；先確認 Edit → Undo 的分組，再 Ctrl+Z 一次 | 每次只撤銷一個原生 undo 步驟；Ctrl+C 本身重做兩次看不出差異，不能只用複製判斷 |
| 來源 Finder | A 開可丟棄的 Finder 資料夾，控制 B 文字 App 做 Ctrl+X／V、Alt+F4 | A 的檔案與視窗不變；B 依開關執行，未儲存文件仍出現確認，不強制關閉 |
| 持鍵跨機 | A 按住 Ctrl，移到 B，B 選取文字後按 C；放 C、再放 Ctrl。交換放鍵順序再測 | 複製正確；放完後普通字母不帶 Command／Control |
| 多鍵盤 | 两把鍵盤分别按住 Ctrl；放開其中一把，再於另一把按 C；最後全部放開 | 剩下那把 Ctrl 仍有效，全部放開後沒有卡鍵 |
| Shift／Alt 重疊 | Ctrl+C 後仍持 Ctrl，加入 Shift＋方向鍵；Alt+Tab 後以不同順序放 Alt／Shift／Ctrl | 不把前一次 Command 帶到後續快捷鍵；原生 App 切換正常結束 |
| 中斷交接 | 持 Ctrl／Shift 時按 Bridge Pause；放開後恢復。再測睡眠、UC 斷線／重連、USB／BT 斷連、切 backend | 中斷後不補做舊動作；放開全部按鍵後新快捷鍵恢復；沒有卡鍵 |
| 原生截圖 | B 按 ⌘⇧3、⌘⇧4、⌘⇧4 後空白鍵選視窗；另測 Win+Shift+S | 存檔後可直接貼到 TextEdit 富文字或其他圖片欄位；圖片是 B 的畫面，沒有來源端重複截圖 |
| 截圖取消 | Esc 取消；圖片處理時 Pause，馬上恢復；再作新截圖 | Esc 不覆寫剪貼簿；舊 Bridge 工作不晚到覆寫；新截圖能正常貼上 |

Native 截圖仍由 macOS 完成。Pause 停止 Bridge 自動複製，但不會替系統關閉已開啟的原生截圖 UI。截圖在 Pause 後才開始、又在恢復後存檔時，可能被視為恢復後新產生的截圖；這和已經進入 Bridge 的舊解碼工作是不同情境。

## 4. 遇到問題提供什麼

記下 A → B 或 B → A、兩台版本、鍵盤是內建／USB／BT、來源及目的 App、實際按鍵與放開順序、HID Ready／接管數、是否 Pause／睡眠／斷線，以及畫面上哪一台發生了什麼。可使用 App 的短期診斷；不要貼真實文件內容或密碼。

先測上述 UC 核心路徑。Remote Desktop、Jump、AnyDesk 等每個軟體各是一條不同輸入路徑；提供確切軟體後再逐項校準，UC 通過不代表所有 Remote 通過。未知或隱藏 PID 的來源仍保持原樣。

只有這些操作實際通過，才能把對應路徑標示已驗收；此表不是預先宣告全部支援。
