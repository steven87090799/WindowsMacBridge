# WindowsMacBridge：實機驗收

這份流程用於確認你實際的鍵盤、輸入法與遠端環境。請使用可丟棄的測試文字與檔案，
不要在密碼欄、重要文件或正在工作的遠端桌面上做故障測試。
原始碼測試通過不等於以下項目通過；沒有操作過的格子請留白。

## 準備（約兩分鐘）

1. 從 Applications 啟動 App；診斷應顯示 EventTap Active、Secure Input OFF。
2. 記下 App 版本、macOS 版本、鍵盤型號、輸入來源。先關掉 Karabiner 中重複的規則。
3. 如果系統曾交換 Control／Command，先記下該鍵盤的設定。不要一次還原全部鍵盤；
   實體 Windows Ctrl 行為應在預設鍵位下另外做對照。
4. 在 TextEdit 新建不需保存的純文字文件，輸入三行測試文字：`Bridge test 123`。
5. 開啟 App 的「5 分鐘診斷」可查看命中的規則及時間；只記規則，不記輸入文字。
   測完關閉。請實際按鍵盤；自動化送鍵可能不經過 EventTap。

## 本機快捷鍵

| 操作 | 通過條件 |
| --- | --- |
| Ctrl+A、C、V | 全選、複製，再貼上得到相同測試文字 |
| Ctrl+X、V | 選取的測試文字移走，再貼回；不是產生 X／V 字母 |
| Ctrl+Z、Y | 復原與重做各一次，文件結果符合預期 |
| Ctrl+F、S、P | 顯示尋找、儲存與列印介面；用取消離開，無需真的列印 |
| 原生 Command+C／V | 仍能照 macOS 原本方式操作 |
| 左右 Ctrl／Shift | 分別測試；放開一邊但仍按著另一邊時狀態正確 |
| Ctrl+Y 先放 Ctrl、Y 暫時不放 | 不應連續輸入 Z，也不應在重按 Ctrl 後復活連發；放開全部後新快捷鍵正常 |
| Ctrl 按住切 App | 在新 App 先放開全部按鍵，再按新快捷鍵才開始翻譯；不重播前個 App 的動作 |
| 本機視窗切換 | 預設 Alt+Tab 原樣通過；啟用逐視窗開關後，Alt+Tab／Alt+Shift+Tab 選擇不同視窗，放開 Alt 才切換；最小化及多螢幕也要測。HID 模式另測舊有持有式映射。 |
| 框選截圖 | 在一般設定確認截圖自動複製已開，實際按 `Shift+Win+S`（`⇧⌘S`），框選 App 視窗中一小塊非敏感區域；確認圖片照常存檔，且直接按 `⌘V` 能貼上圖片。另按 `Ctrl+Shift+S`，確認沒有進入截圖，並保留該 Profile 的另存新檔翻譯或原樣通過；再按 `⇧⌘4`，確認維持 macOS 原本行為。取消框選時剪貼簿不變。 |

再到 Codex 的**未送出聊天文字框**用相同測試文字做 Ctrl+A/C/X/V/Z；不要送出。
Codex 的預設 Profile 適合聊天；若使用它的內建 Terminal，需改成 IDE 保護模式。

## Safari／YouTube 與原生視窗

- 先處理 Safari 的待確認對話框；分別用視窗綠色按鈕、顯示方式選單進入／離開全螢幕。
- 在 YouTube 播放器按全螢幕按鈕，再用 Escape 離開；確認搜尋欄沒有焦點後測 F、K、空白與方向鍵。
- 測原生 Control+Command+F、Command+M、Command+Tab，再測一次 Ctrl+C／V 後重做全螢幕。
- 各在 Bridge 完全結束與 EventTap Active 下測一次。記錄是否只有啟用才出錯；UI 自動化結果不能代替實體快捷鍵驗收。

## Terminal 與中文

- Terminal.app 開啟新的本機視窗，輸入 `sleep 30`，按 Ctrl+C 應立即回到 shell 提示。
  不應執行 Copy；App 應判定 Terminal。再於未執行的測試命令檢查 Ctrl+A／E／U。
- 唯音輸入三個測試詞，檢查組字、選字、Backspace、Enter、Shift 與 Caps Lock 切換。
  完成組字後測 Ctrl+A/C/V；另測候選選單開啟時，避免跳字、重複字或選字中斷。
- 在 ABC 重複同一組快捷鍵。若唯音不正常而 ABC 正常，先關閉「中文／唯音實體鍵位快捷鍵」，
  再記錄發生問題的 App、鍵盤與操作，不需提供實際文件文字。
- 真正的密碼輸入期間，Secure Input 若啟用，App 應停止翻譯。不要為了測試關閉安全輸入。
  離開敏感欄位並放開所有按鍵後恢復。若唯音發出 Safari 警告，先離開 Safari 密碼欄或正常結束 Safari。

## 遠端與 VM（由你選擇測試時機）

每個 Client 分開驗收，記錄 Client／遠端 Windows 版本與它自己的鍵盤轉送設定。
先暫停 Bridge 做一次基準，再開啟 Bridge 重做；結果應相同。

| 操作 | 要確認的結果 |
| --- | --- |
| 前景切到 Client | Menu Bar 顯示 Remote Windows／Virtual Machine；本機不翻譯 |
| 遠端記事本 Ctrl+A/C/X/V/Z/Y | Windows 收到原按鍵；資料結果與暫停 Bridge 時相同 |
| Alt+Tab | 由 Client 的轉送／全螢幕設定決定；與 Bridge 暫停時一致 |
| Ctrl+Alt+Delete | 優先用 Client 的「傳送 Ctrl+Alt+Delete」功能；Bridge 不代替它 |
| 本機／遠端 Clipboard | 使用 `Bridge test 123` 測雙向文字；功能由 Client 的同步設定控制 |
| 視窗／全螢幕、多螢幕 | 各測一次快捷鍵，再切回本機；不留住 Ctrl／Shift／Option |
| Ctrl 按住進出 Client | 切換後先放開全部按鍵再測；本機快捷鍵不應在遠端延遲重播 |

建議先測你實際使用的 AweSun、Parsec 或 Parallels；沒有使用的 Client 不必勾選通過。
Microsoft Windows App、Jump、AnyDesk、RustDesk、VMware、UTM 等需另做同樣對照。
Chrome Remote Desktop 等瀏覽器分頁無法單靠 App ID 自動辨識；使用專用瀏覽器並指定 Remote Profile。

## 暫停、恢復與裝置

1. Menu Bar 暫停 5 分鐘，應恢復 macOS 原按鍵；等待時間到後，放開全部按鍵再試 Ctrl+C。
2. 按 Control+Option+Command+P，確認暫停；用 Menu Bar「恢復／重啟引擎」恢復。
3. 保存工作後，讓 Mac 正常睡眠，再喚醒；確認 App 仍在、EventTap Active、普通打字正常。
4. USB／Bluetooth 分別測試斷線重連。重連後先放開全部按鍵，再測快捷鍵。
5. 正常結束 App，普通 macOS 按鍵應立即恢復；重新開啟只應有一個 Menu Bar 圖示。
6. 權限撤銷／Fast User Switching／登出重登入只在保存工作後驗收；未授權時應停止翻譯，
   不反覆彈窗、不高 CPU。重新授權後按「恢復／重啟引擎」。

強制終止、真實 EventTap timeout 與 HID 接管測試需要專用測試時段及可用滑鼠／第二把鍵盤。
HID 不在一般 DMG 的安裝流程內，不要為了完成本機快捷鍵驗收而安裝 Driver。

## MacBook Fn／Ctrl 與通用控制

先放開所有按鍵，用可丟棄的文字文件測試。MacBook 開啟 Fn／Ctrl 模式並確認「已交換」，Mac mini 應顯示等待、外接鍵盤不變。

| 鍵盤來源 → 操作目標 | 必須確認 |
| --- | --- |
| MacBook 內建 → MacBook | Fn+C／V 執行 Ctrl 複製／貼上；原左 Ctrl+Delete／方向鍵執行 Fn 的前刪／Home／End 行為 |
| MacBook 內建 → Mac mini（通用控制） | 相同按鍵結果；不重複交換，切回來源端不留下 Ctrl hold |
| Mac mini 外接 → MacBook（通用控制） | Ctrl+C／V 仍使用外接 Ctrl，外接 Fn 不因接收端模式被交換 |
| MacBook 外接 → 任一臺 | 保留外接配置；兩把鍵盤交替使用時沒有卡住的修飾鍵 |
| 來源／接收端 Terminal、Remote、VM、Game | 交換後的 Ctrl 仍依既有 Profile 原樣通過，不發出本機 Windows 動作 |
| 內建鍵盤模式關閉／正常退出／重開／睡眠／重新登入 | 關閉與退出還原；重開依保存選項套用；睡眠與登入恢復無按鍵殘留 |

若任何跨機組合不一致，記錄來源與接收端版本、鍵盤、Profile 及開關狀態。原生 API 的讀回與虛擬服務排除不證明 Universal Control 實際轉送結果。

## 回報方式

提供「版本、鍵盤、App／Profile、操作步驟、預期與實際結果、暫停 Bridge 後是否仍發生」。
可以附 App 診斷頁的狀態／計數，不需貼上密碼、文件、Clipboard 或完整按鍵歷史。
