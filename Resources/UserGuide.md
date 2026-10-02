> 授權頁已平鋪八項，每項都有必要／選用與系統位置。主 App「輸入監控」也必須核准，不能只開鍵盤控制。綠色僅代表 native 檢查通過；未檢查、待核准及已安裝都不算通過。⌘⇧3／⌘⇧4 自動複製另列截圖資料夾存取，程式自動申請目前截圖資料夾，確認實際可讀才綠色。

> 單一 App 安裝版（0.5.17 / build 36）：解壓後開啟 WindowsMacBridge.app，第一次開啟時自動完成安裝。App、背景鍵盤元件及 Driver 都由同一次安裝處理，完成後自動開啟權限清單。Windows 快捷鍵、截圖自動複製及所有鍵盤模式已準備；MacBook 偵測到內建 Apple 鍵盤時啟用 Fn／Ctrl 交換。你只需逐項核准系統權限，不需執行指令、加入元件或選擇後端。主畫面直接顯示八項權限，每列只有「開啟設定」，回來後自動檢查；上方保留「權限」、「一般設定」、「唯音與輸入法」、「App 規則」、「診斷」分頁，不另設進階設定。Driver 保留原廠 Karabiner 名稱／圖示。

# WindowsMacBridge 0.5.17（build 36）— 操作說明

截圖尚在框選或圖片轉換時，關閉開關會取消該次自動複製；即使馬上重開，也不會複製上一輪圖片。已儲存的圖片保留。原生框選仍可按 Esc 取消；同一時間只接受一輪截圖。Pause、backend、session、Secure Input 或設定世代改變會取消舊工作；120 秒逾時，權限、程序、磁碟、解碼與編碼失敗各自顯示原因。截圖 Event Tap 在 60 秒內第三次停用時停止自動重試並顯示錯誤，放開按鍵後重開截圖開關即可重新檢查。

Finder 右鍵路徑選單需要 App 正在執行及 Finder Mode 已開啟。設定同步僅使用原生通知傳送開／關，不依賴 App Group；免費簽章版本的擴充功能保留沙盒，沒有新增輪詢。

兩台 Mac 的安裝順序與逐項測試，見 [TwoMacAcceptance.md](TwoMacAcceptance.md)。

## 最快開始

1. 解壓單一 App ZIP，開啟 `WindowsMacBridge.app`，依系統提示完成管理員驗證。程式自動安裝到「應用程式」並重新開啟。
2. 在「權限設定」頁逐項核准。只有原生檢查確認通過才顯示綠色；更新後同名舊項目可能需要重新核准目前版本。若系統要求結束並重開 App，請完成此動作。
3. 第 6 項提出背景键盤元件輸入監控要求；第 7 項到驅動程式延伸功能核准 Karabiner‑VirtualHIDDevice；第 8 項開啟截圖資料夾存取；程式會處理資料夾申請，你不用選取路徑。必要項目完成後，HID 的 Ready 且接管數大於零才表示實體快捷鍵已啟動。
4. 在 TextEdit 的可丟棄文件試 Ctrl+A／C／V／Z。再按 Win+Shift+S 框選，存檔後直接貼上，不用點開縮圖；⌘⇧3／⌘⇧4 也自動複製。macOS 浮動縮圖可能延後存檔數秒。

這是待實機驗收的修復候選版，適用 Apple Silicon、macOS 14+，不需要購買 Developer 帳號。App 使用 ad-hoc 簽章，沒有 Apple 公證；若 macOS 阻擋，嘗試開啟後到「系統設定 → 隱私權與安全性」使用系統提供的「仍要打開」。不要關閉 Gatekeeper／SIP 或清除 quarantine。

EventTap 備援不需安裝 Driver，但不能提供可靠的逐裝置偏好與通用控制來源分流。所有鍵盤使用 Windows Experience 時，HID 保留 App-sensitive 原始按鍵，由實際接收事件的 Mac 依自己的 App 翻譯；兩台 Mac 均需新版 App/helper。混合 Native Mac 裝置時，無法確定跨機來源，Finder／AX／HID 截圖增強停用。純 HID 系統快捷鍵先編碼，再交由 macOS／UC 傳送。

實體鍵盤、中文組字、Terminal、遠端與睡眠恢復驗收，請按 App 的「實機驗收步驟」，
或閱讀同資料夾的 [AcceptanceGuide.md](AcceptanceGuide.md)。未操作過的情境保留為未驗收。

## 預設值

| 設定 | 新安裝預設 | 用途 |
| --- | --- | --- |
| Windows 快捷鍵 | 開 | 本機 Ctrl 快捷鍵轉為 macOS 操作 |
| 輸入方式 | 裝置 HID | 實體來源先正規化；需要 helper／Driver；舊版 EventTap 保留 |
| 鍵盤範圍 | 所有鍵盤 | 內建、USB、Bluetooth 均使用同一套快捷鍵規則 |
| MacBook Fn／Ctrl 交換 | 關 | 保留實體 Control 與 Fn／Globe；舊版明確選項保留 |
| Codex／ChatGPT App | Default macOS | 依 `com.openai.codex` 套用聊天／文字操作 |
| Terminal／其他 IDE | 原樣通過 | 保護 Unix 與內嵌終端機 Ctrl 快捷鍵 |
| Remote／VM／Game | 原樣通過 | 不在本機翻譯或切換輸入法 |
| Finder 加強 | 關 | 尚未開啟檔案開啟、改名、剪下移動 |
| 視窗切換 | macOS 原生 | `⌘Tab` 逐 App；`⌘\`` 切換同一 App 的視窗 |
| Windows 文字游標 | 開 | 保留舊版 Ctrl 文字導覽並新增 Home／End |
| Alt+F4 | 關 | 按目前視窗的 AX 關閉按鈕，保留未儲存提示 |
| Finder 亮度增加 → Enter | 關 | 只在本機 Finder 與 Finder 增強啟用時生效 |
| Remote Input | 各來源自動 | Google host 原始 Ctrl 轉換、Command 通過；未知來源可逐一校準 |
| PrintScreen | 框選 | 可改為傳統全螢幕複製 |
| Windows 鍵位置 | Command | 標準實體 Win／Apple Command 鍵位；舊版明確選擇保留 |
| Win+R／Win+I／Win+Tab | 關／關／關 | 可選 Spotlight／系統設定／Mission Control |
| 截圖自動複製 | 開 | `⌘⇧3`／`⌘⇧4`／`Shift+Win+S` 截圖後自動複製 |
| 中文／唯音實體鍵位快捷鍵 | 開 | 底層 ABC／U.S. 的中文來源也翻譯快捷鍵 |
| 輸入法守護／切換快捷鍵 | 關／關 | 保留原本輸入來源，不自動改成唯音 |
| 守護修正延遲／啟動等待 | 400 ms／1500 ms | 只影響守護，不增加按鍵翻譯延遲 |
| 切換快捷鍵組合 | Control+Option+Command+Space | 功能開啟後才註冊 |
| 登入啟動／短期診斷 | 由截圖功能註冊／關 | 登入項目可能需在 macOS 系統設定核准 |

「套用建議預設」重新設定 Windows 快捷鍵、輸入方式、範圍、Finder、中文 IME 與 Codex 規則；保留其他自訂 App 規則、Fn／Ctrl 選擇、輸入法及登入設定。設定有損壞或版本不支援時，安全停用，不強行啟用。

## MacBook 內建鍵盤模式

新安裝及舊版缺欄位均保留 Control 與 Fn／Globe。內建與 Apple 鍵盤不因品牌而被排除；在 HID 已接管且 Windows Experience 啟用時，Control+C 和外接鍵盤使用同一套複製規則。「交換 Fn／地球鍵與左 Ctrl」是額外選項，舊版明確保存的選擇不被覆寫。啟用才交換內建 Fn／左 Ctrl，外接鍵盤不交換；請放開按鍵後切換。

通用控制兩種方向都能使用同一份設定：只在來源 MacBook 交換實體內建鍵盤，另一臺收到的虛擬服務不會再次交換；外接鍵盤操控 MacBook 時仍保持外接排列。實際跨機 Ctrl／Fn、中文組字及睡眠恢復需按驗收指南測試，未測之前不視為已驗收。

這個原生選項不需安裝 HID。選進階 HID 時，先還原原生交換，再由 helper 只在接管的內建鍵盤服務依同一開關交換；外接鍵盤不交換 Fn／Ctrl。Remote／VM／Game 的 HID 模式會交還實體鍵盤，該情境的 Fn／Ctrl 交換需實體驗收，不能只靠離線測試推定。全域 Pause 同步停止翻譯、截圖、Finder／輸入法工作與 Fn／Ctrl 映射；仍有按鍵按住時延後原生映射還原，等待放開後才完成。

關閉或正常退出還原本程式的交換，其他映射保留。系統或其他工具已占用 Fn／Ctrl 時顯示衝突，先在對應工具還原這把內建鍵盤，再按「重新檢查鍵盤模式」。強制終止可能留下暫存映射，重新開啟可依還原紀錄恢復；重新開機清除暫存映射。App 的登入啟動依保存的開關重新套用，若待核准，按授權清單的登入項目前往系統設定。診斷紀錄為 `~/Library/Logs/WindowsMacBridge/KeyboardMapping.log`。

## 授權清單

鍵盤控制合併成一列：macOS 27 顯示「裝置控制和資料取用」，較舊系統顯示「輔助使用」。按「開啟設定」會呼叫缺少的原生要求 API，再重新驗證目前 App；開啟設定頁本身不代表授權成功。主 App 與 HID helper 的輸入監控各自列出。螢幕錄製、登入啟動、Finder 擴充、Driver 核准及截圖資料夾存取也固定列出，依目前功能標明必要／選用。背景元件的權限檢查不會接管鍵盤，在尚未啟動 HID 時也能提出授權要求。

App 啟動、開啟設定及返回前景時會重新檢查，也可按「重新檢查」。狀態來自目前 App 的原生 API；系統的同名舊項目顯示開啟，不代表新版已取得權限。每項按鈕會處理目前版本的權限申請，然後開啟對應系統設定。

「前往開啟」只跳到系統設定。按下按鈕不代表已授權，也不會自行啟用登入項目；返回 App 後重新檢查，macOS 確認授權才顯示綠勾，拒絕／取消仍顯示紅叉。若 macOS 要求「結束並重新打開」才能套用變更，請完成重啟。

## 一般

- **Windows 快捷鍵**：開啟後翻譯既有 29 組一般規則與 19 組瀏覽器規則，涵蓋複製、貼上、復原、儲存、分頁與文字導覽；關閉不會連帶關閉輸入法守護。
- **EventTap 備援**：只在未識別為遠端／UC／自身輸出的 hardware 事件上翻譯；沒有可靠鍵盤 device ID。存在 Native Mac 裝置偏好或指定範圍時停止備援的實體翻譯並顯示原因，不能忽略你的裝置選擇。已辨識遠端仍可獨立處理。自製視窗切換器已移除；遠端 Alt+Tab 只是輸出 macOS 原生 Command+Tab。
- **HID**：進階裝置測試後端，需要另裝 root helper 與官方 VirtualHID Driver。「所有支援的鍵盤」接管符合安全 descriptor 的內建及外接鍵盤；另保留內建／Apple VID 1452/PID 834 範圍。複合、虛擬或未知 descriptor 維持原生。依目前 Win 鍵位置配置 Option／Command，內建鍵盤依同一 Fn／Ctrl 開關配置，Finder／文字／Alt+F4／Win+R/I/Tab 開關會傳給 helper。切換輸入方式會選擇對應範圍。
- **鍵盤範圍**：EventTap 使用所有鍵盤，HID 使用指定範圍。EventTap 選內建限定時停止翻譯，避免錯誤地套用到全部鍵盤。
- **Finder 加強**：確認在檔案列表才啟用開啟、改名、刪除與 Ctrl+X／V 移動。Ctrl+X 先執行 Copy 並記住剪下狀態，Ctrl+V 再交由 Finder 的 Move 執行。開資料夾、上一層與切換路徑保持剪下狀態；剪貼簿更新、切換 App、暫停或 5 分鐘後取消標記；不保證 Move 已成功。Shift+Delete 必須另外啟用並逐次確認。右鍵路徑選單由 Finder Sync 提供，請在系統的 Finder 擴充功能設定啟用；「顯示目前資料夾路徑」子選單優先顯示選取項目的完整 POSIX 路徑，並有「複製此路徑」。只有按下複製才寫入剪貼簿。
- **Windows 文字游標／Alt+F4**：Ctrl+方向鍵按單字移動，Home／End 到行首行尾，Ctrl+Home／End 到文件邊界，Shift 組合選取。Alt+F4 使用 AX 關閉目前視窗，未儲存內容仍由 App 確認；找不到可用關閉按鈕時顯示原因。沒有 Command+W 或 Command+Q fallback。
- **Windows 鍵位置**：EventTap 收到這把鍵盤的 Win 為 Option 時選 Option，收到 Command 時選 Command。截圖、Win+E／Win+L 和選配 Win+R／I／Tab 使用此鍵；Alt+F4／瀏覽器上一頁、下一頁使用另一鍵。Alt+Tab 由 macOS 原生鍵位決定。EventTap 不更改 Ctrl、macOS 系統修飾鍵或其他 App 鍵位。HID 模式會在接管的裝置上依此選擇輸出適合原生 `⌘Tab` 的 Alt；Win+Shift+S／PrintScreen 框選及全螢幕截圖改寫為原生 macOS 截圖，完成存檔後自動複製。Alt+PrintScreen 保留經目的端驗證的視窗擷取；同一事件不再重複處理。
- **Win+R／Win+I／Win+Tab**：各自預設關閉、獨立選用，依序對應 Spotlight（⌘Space）、系統設定及 Mission Control（⌃↑）。只有本機 Default macOS Profile 攔截；若 macOS 系統快捷鍵已改動，Spotlight／Mission Control 需依系統設定調整。
- **截圖自動複製**：預設開啟。`Shift+Win+S` 進入框選，Alt+PrintScreen 擷取目前視窗，Win+PrintScreen 全螢幕存檔，PrintScreen 可選框選或傳統全螢幕複製；完成時存檔並複製 PNG 供 `⌘V`。Esc 取消不改剪貼簿。EventTap 的 PrintScreen 對應 F13 位置，需核對實體鍵盤輸出。`Ctrl+Shift+S` 不會觸發截圖，仍依 App Profile 保留另存新檔翻譯或原樣通過。`⌘⇧3`／`⌘⇧4` 保留系統全螢幕、框選與空白鍵選視窗；系統完成存檔後自動複製，不必點開縮圖。若啟用浮動縮圖，可能需等縮圖消失；要即時複製可用 `Win+Shift+S`。儲存位置使用 macOS 截圖設定；更改位置後按截圖重新檢查或重開開關。只有啟用後新增、帶 Apple 截圖標記的圖片會被處理，不掃描歷史圖片；Bridge 自己產生的圖片不重複複製。關閉時移除截圖攔截與檔案事件觀察。Remote／VM／Game 等保護 Profile 原樣通過。
- **登入啟動**：先將 App 放進 /Applications。截圖自動複製會註冊登入項目；若系統顯示待核准，按「開啟登入項目設定」檢查。關閉截圖功能時只移除它新增的註冊。
- **鍵盤控制**：同一系統授權頁提供視窗存取與按鍵送出能力，但 App 必須分別驗證 Accessibility／PostEvent 原生 API。沒有把紅叉改成假成功，也沒有移除釋放 synthetic key 所需的授權檢查。更新後若系統舊項目已開啟而目前 App 仍未取得，按該項「開啟設定」，核准目前版本後依系統提示重新啟動 App。ad-hoc 簽章更新後可能需要重新授權。
- **App 輸入監控**：用「要求 App 輸入監控」提出請求；EventTap 的可用性依系統授權而定。HID helper 必須另外取得自己的輸入監控權限。
- **中文／唯音快捷鍵**：預設開啟，在底層 ABC／U.S. 的中文輸入法也可依實體鍵位翻譯。不讀取組字內容，無法可靠判斷正在選字；若 App 候選或組字行為有衝突，可關閉此項，只在 ABC／U.S. 來源使用翻譯。
- **暫停**：設定頁提供 5 分鐘或至重啟，Menu Bar 另有 15 分鐘／1 小時。同步暫停 HID／EventTap、截圖、Finder、Fn／Ctrl 與輸入法守護；「恢復／重啟引擎」取消暫停與穿透，重新嘗試啟動。
- **緊急操作**：右 Option+P 切換穿透，Control+Option+Command+P 暫停。在 Remote／VM／Game 的 HID 原生鍵流不攔截這些熱鍵，請從 Menu Bar 暫停／結束。

鍵盤內雙向箭頭是啟用圖示，雙直線是暫停／停用圖示。這代表你的 Windows Mode 開關；是否正在翻譯仍需看 Menu Bar 的目前 App／Profile 與狀態。圖示不含文字，隨 macOS 明暗主題調整。

### 已經改過按鍵位置

macOS 的「修飾鍵」交換與 Karabiner 映射都會影響程式實際收到的按鍵。程式不會改動或還原這些設定。先停用 Karabiner 中重複的規則，測試實際的 Ctrl／Command；需要保留實體 Windows Ctrl 語意時，再把該鍵盤在「系統設定 → 鍵盤 → 鍵盤快速鍵 → 修飾鍵」還原。不同鍵盤有各自設定，不要一次還原全部。

## App 規則

### Safari／YouTube 全螢幕排查

先查看 Safari 是否有待確認的網站、登入或「開啟其他 App」對話框，處理或取消後再試。
分別測視窗綠色按鈕、Safari 顯示方式選單，以及 YouTube 播放器全螢幕按鈕。
F／Escape 應保持原樣，但不要在搜尋欄中測 F。

若仍失敗，從 Menu Bar 完全結束 WindowsMacBridge，再重試相同操作，記錄是否仍發生。
EventTap 不攔截滑鼠，不翻譯無修飾鍵 F／Escape 或原生 Control+Command+F。
只有啟用時失敗，才進一步排查映射；兩者都失敗時先保存工作，再考慮正常重啟 Safari。
不必重設全部鍵盤或降低 macOS 安全設定。程式不會自動關閉其他 App 的對話框。

### 指定模式

「最近使用」可直接指定模式；「選擇其他 App」選取 .app 後先加入 Disabled，再從選單改模式。變更立即儲存，不需重啟。「移除」刪除自訂規則，回到內建判定。

| Profile | 行為與使用情境 |
| --- | --- |
| Default macOS | 本機 Windows 快捷鍵翻譯；手動選擇會覆寫原本保護 |
| Terminal | Ctrl+C／D／Z 等 shell 意義維持原樣；HID 整個鍵盤穿透，EventTap 仍保留部分本機系統動作 |
| IDE | 保護編輯器、除錯器與內嵌 Terminal 的原生 Ctrl 操作 |
| Remote Session | 整個遠端 Client 原樣通過，停止本機動作及輸入法切換；Windows／Mac 目標皆適用 |
| Virtual Machine | VM 原樣通過；輸入捕捉由 VM 控制 |
| Game | 遊戲原樣通過，停止本機動作及輸入法切換 |
| Disabled | 不套用本機翻譯或輸入法守護 |

**Codex 已依「只用聊天與文字輸入」預設 Default macOS。** 如果改用內建終端機，改成 IDE 或移除 Codex 規則，避免 Ctrl+C 變成 Copy。移除此規則後不會因下次重啟重新加入；「套用建議預設」才會再加入。

App 的 Remote Session 規則保護「本機正在操作遠端 Client」的原始按鍵。它與「其他電腦控制這台 Mac」不同：後者依 CGEvent 來源 PID、程序簽章及來源偏好獨立處理。一般 Chrome 不被當作 Google host。Google host Automatic 轉換明確的 raw Ctrl／Home／End／Alt+Tab，已是 Command 的快捷鍵保持原樣；有歧義的 Win／Option 組合需要該來源的 Windows 語意設定。

Remote Advanced 顯示實際來源、Known／Likely／Unknown、語意與 Detected／Generic／Unknown；目前沒有遠端被列為 Verified。未知 producer 保留原樣，按「校準這個來源一次」後，在遠端按 Ctrl+C，最多 60 秒辨識此組合收到的是 Control 或 Command，保存到此來源；不保存普通打字。不用切 Sender／Receiver，遠端偏好也不影響其他鍵盤或 UC。

每個來源有獨立按鍵帳本；程序消失、host session／pause／Secure Input／policy 改變會清理自己的輸出。沒有可觀察 disconnect 訊號時，持有的遠端合成輸出在 60 秒沒有來源事件後安全失效，長時間靜止持鍵需要重新放開再按。來源 PID 被軟體隱藏／改成零、未知虛擬 HID 或共享 host 的多個 peer，不能保證自動區分；請按驗收指南逐一測試。Client 是否轉送 Alt+Tab、Win+Shift+S 等本機保留快捷鍵，仍由 Client／來源 OS 決定。

## 唯音與輸入法

- **輸入法守護**：需另裝唯音。從 macOS 狀態欄或系統快捷鍵切換後保持使用者的來源；ABC 和其他輸入法都適用。重新啟用、重新偵測、喚醒及重啟採用當前來源，不切回唯音。來源通知無法辨識發起者，因此所有非本程式確認的切換都保守保留。
- **唯音繁體／ABC 按鈕**：立即切換來源；Remote／VM／Game／Disabled、暫停或來源切換受保護時不可使用。Secure Input 期間延後。
- **停止偵測多久**：在「暫停自動偵測」選 5／15／30 分鐘、1 小時或直到手動恢復，再按「暫停偵測」；Menu Bar 也提供這些選項。只暫停輸入法自動修正，Windows 快捷鍵照常。到期或按「恢復偵測」後保持目前輸入法。截止時間和選項持久保存，重啟、更新及睡眠不重新倒數；沒有持續輪詢。
- **重新偵測**：安裝唯音或新增 ABC 後重新尋找來源；來源不存在時顯示原因。
- **切換快捷鍵**：獨立開關，開啟後在唯音與 ABC 之間切換。⌃=Control、⌥=Option、⌘=Command、⇧=Shift；預設組合 Control+Option+Command+Space。遇到衝突可換組合，註冊失敗時嘗試保留原組合。
- **修正延遲**：200–1200 ms，每次調整 50 ms。供程式自身切換失敗後的有界重試使用；外部切換會立即保留，不等待此延遲。
- **啟動等待**：0–5000 ms，每次調整 250 ms。登入時輸入法服務尚未就緒，可增加等待。
- **更新診斷**：展開來源診斷後重新讀取來源 ID、切換結果與狀態；不讀鍵盤文字。守護日誌最多兩個約 512 KiB 檔案。
- **輸入法統計**：顯示自動修正成功、程式切回唯音、保留來源切換、切換失敗、Secure Input 等待、最後成功時間及最近恢復時間。紀錄持久保存，近期恢復時間最多 20 筆。首次執行新版自動合併舊版唯音助手的六個統計欄位，只匯入一次，不匯入舊設定或啟動舊程式。Resident／Physical footprint 只在開啟本頁、按「重新整理統計」或更新診斷時量測。

## 診斷

- **版本與編譯資訊**：顯示版本、Build、UTC 編譯時間、Git commit、原始碼狀態與 Bundle ID，可複製供問題回報。
- **目前 App／Profile**：判斷現在為何翻譯或穿透。開啟本設定視窗時，本程式自己是穿透狀態。
- **Event Tap Active**：EventTap 後端有鍵盤攔截；HID 請看 Helper／Driver 與接管數。
- **Secure Input ON**：macOS 安全輸入期間不翻譯，不嘗試繞過；離開後放開所有按鍵。
- **處理／翻譯事件計數**：只含數量，不含內容；穿透情境有處理但無翻譯屬正常。
- **最大觀測時間**：引擎 callback 時間，1000 µs=1 ms；不包括 App、OS、網路的完整延遲。
- **5 分鐘診斷**：預設關閉，最多 128 筆規則／App／時間只存在記憶體，關閉後清除。普通打字不產生逐鍵紀錄；HID 顯示計數與最近命中規則。

鍵盤事件與剪貼簿不會上傳，不保存密碼、OTP 或一般打字；不是剪貼簿歷史工具。

## 進階 HID／停止與移除

單一 App 第一次開啟會安裝所有內含元件，管理員驗證由系統處理；新版 HID 預設只會在 helper／Driver Ready、所有安全條件成立時接管支援的實體裝置。不支援 descriptor 保留原生。

先從 Menu Bar 暫停／結束。只用 EventTap 時，將 App 移到垃圾桶即可停止使用；macOS 的登入項目與權限可自行移除，設定偏好會保留。若裝過 helper，使用 Uninstall.command 移除本工具服務；共用官方 Driver 保留，避免影響其他軟體。

更新中止時，App 會顯示待復原並停用相關輸入。依系統提示完成核准或重新開機，再開啟下载的 App；程式先處理待復原交易，再完成安裝。已驗證相容的官方 8.0.0–8.6.0 Driver 沿用且不改寫；未知／不相容 ABI 停止，不能以回復 App 推定 DriverKit 已還原。

本版暫停 Finder 亮度鍵 Enter 轉換，亮度保持原生功能。來源端尚無 consumer key 的目的端 App 證據；舊設定可清除。標準相對滑鼠／32 個以內按鈕的 keyboard composite 可在整份 descriptor 可轉送時擷取；未知、絕對座標及 multitouch service 保留原生輸入。沒有將它們列為實機 Verified。
