# WindowsMacBridge

將 Windows 快捷鍵、MacBook 鍵位輔助、截圖與唯音／ABC 輸入法管理整合在同一個 macOS 選單列 App，以 Swift、AppKit、SwiftUI 與 macOS 原生 API 實作。

**系統需求：Apple Silicon、macOS 14 以上。** 目前 `main` 原始碼版本為 **0.6.0（build 40）修復候選版**；下載包版本以 [GitHub Releases](https://github.com/steven87090799/WindowsMacBridge/releases) 為準。合併原始碼不代表已發布新版安裝包；實體 HID、Universal Control、遠端、TCC 授權與安裝復原仍需實機驗收，目前不宣稱已可正式上線或完整取代 Karabiner。

本文介紹目前來源已實作的功能；新安裝預設指完整單一 App 首次完成安裝準備後的設定。最新權限與分頁流程見 [權限修復紀錄](Docs/SimplePermissions-2026-10-02.md)，鍵盤與資源審查見 [八類功能複查](Docs/ReviewerAudit-2026-10-02.md)，雙機操作見 [兩台 Mac 驗收](Resources/TwoMacAcceptance.md)。

## 功能總覽

| 功能 | 可以做什麼 | 新安裝預設 |
| --- | --- | --- |
| Windows 一般快捷鍵 | Ctrl 複製、剪下、貼上、全選、復原、儲存、尋找、列印等 | 開啟 |
| 瀏覽器快捷鍵 | 分頁、網址列、重新整理、書籤、上一頁／下一頁與分頁編號 | 隨 Windows 快捷鍵開啟 |
| Windows 文字游標 | 單字移動／刪除、行首行尾、文件邊界與 Shift 選取 | 開啟 |
| Finder 增強 | Enter 開啟、F2 改名、剪下移動、刪除、上一層與資料夾操作 | 開啟；永久刪除另行開啟 |
| Finder 右鍵路徑 | 顯示 POSIX 路徑、複製資料夾或選取項目完整路徑 | 需開啟 Finder 增強並核准擴充功能 |
| Windows 系統操作 | Win+E 開 Finder、Win+L 鎖定、Ctrl+Shift+Esc 開活動監視器 | 隨 Windows 快捷鍵開啟 |
| 額外 Win 操作 | Win+R 開 Spotlight、Win+I 開系統設定、Win+Tab 開 Mission Control | 開啟 |
| Alt+F4 | 關閉目前視窗，保留 App 的未儲存內容提示 | 開啟 |
| 截圖自動複製 | Windows 截圖及原生 ⌘⇧3／⌘⇧4 存檔後複製 PNG | 開啟 |
| MacBook Fn／Ctrl 交換 | 只交換本機內建鍵盤的 Fn／Globe 與左 Ctrl | MacBook 開啟；桌上型 Mac 關閉 |
| App Profiles | 依 App 決定翻譯或穿透，保護 Terminal、IDE、遠端、VM 與遊戲 | 內建判定；Codex 聊天另有預設 |
| 遠端／通用控制角色 | 手動指定在哪一端翻譯，避免重複轉換 | 本機／依 App 規則 |
| 中文／唯音快捷鍵 | 在底層 ABC／U.S. 配置的輸入法，依實體鍵位翻譯快捷鍵 | 開啟 |
| 唯音／ABC 守護與切換 | 保留使用者來源、明確切換、有界重試與暫停偵測 | 守護與切換熱鍵各自關閉 |
| 裝置 HID 後端 | 接管支援的實體鍵盤，依裝置處理修飾鍵、Fn 與 consumer 鍵 | 預設 HID；EventTap 可供相容備援 |
| 授權與登入啟動 | 權限狀態、設定入口、原生登入項目 | 截圖功能會註冊登入項目，可能需核准 |
| 暫停、恢復與診斷 | 全域暫停、緊急穿透、計數、版本資訊與短期規則診斷 | 診斷關閉 |

首次安裝準備會啟用 Windows、Finder、視窗及截圖功能；保留 App／Remote／裝置規則與 Win 鍵位置，永久刪除及亮度鍵轉 Enter 預設關閉。完成後仍可在一般設定調整。

## 安裝與開始使用

1. 點兩下完整單一 App DMG，先從選單列結束舊版，將 `WindowsMacBridge.app` 拖進「應用程式」取代，再從那裡開啟。程式自動準備內含鍵盤處理與共用 Driver，需要時完成系統管理員驗證。
2. 上方保留「權限」、「一般設定」、「唯音與輸入法」、「App 規則」、「診斷」分頁，沒有獨立進階設定或安裝／修復按鈕。
3. 權限頁平鋪七項，每列按「開啟設定」，核准後回來自動檢查，確認通過才亮綠燈。不需加入元件或選截圖資料夾；若系統要求重開 App 或重開機，依提示完成。
4. 權限完成後，用 ABC 與可丟棄的文字文件試 `Ctrl+A/C/X/V/Z`，再確認截圖可貼上。兩台 Mac 的 Universal Control 與 Driver 恢復仍需實機驗收。

單一 App 下載包是否已發布，以 [GitHub Releases](https://github.com/steven87090799/WindowsMacBridge/releases) 為準。一般 DMG 不包含 HID 安裝 payload，不能當成上述完整安裝版。「套用建議預設」會選 HID／所有鍵盤、開啟 Windows／中文快捷鍵、指定 Codex 為 Default macOS，並關閉 Finder 增強；其他 App 規則與選用功能依實作保留。詳細操作見 [使用指南](Resources/UserGuide.md)。

## Windows 一般與文字快捷鍵

以下需 Windows 快捷鍵開啟、輸入來源配置受支援及目前 App 使用 **Default macOS**。實際操作由接收 App 決定，例如 App 沒有列印或另存新檔選單時，映射不會替它新增功能。規則使用實體 ANSI 鍵位與精確修飾鍵，不會把所有 Ctrl 組合一律換成 Command。

符號：`⌃`＝Control、`⌥`＝Option、`⌘`＝Command、`⇧`＝Shift。`Win` 表示設定中選擇的 Option 或 Command，`Alt` 使用另一個修飾鍵。新安裝預設 Win=Command，既有明確鍵位選擇保留，仍須依實際鍵盤輸出調整。

### 一般操作

| Windows 按鍵 | macOS 輸出 | 常見用途 |
| --- | --- | --- |
| Ctrl+C／X／V | ⌘C／X／V | 複製／剪下／貼上 |
| Ctrl+A | ⌘A | 全選 |
| Ctrl+Z | ⌘Z | 復原 |
| Ctrl+Y | ⇧⌘Z | 重做 |
| Ctrl+S | ⌘S | 儲存 |
| Ctrl+Shift+S | ⇧⌘S | 另存新檔或 App 對應操作 |
| Ctrl+F | ⌘F | 尋找 |
| Ctrl+P | ⌘P | 列印 |
| Ctrl+O／N | ⌘O／N | 開啟／新增 |
| Ctrl+W／Shift+W | ⌘W／⇧⌘W | 關閉分頁／視窗或 App 對應操作 |
| Ctrl+, | ⌘, | App 設定 |
| Ctrl+=／Shift+= | ⌘=／⇧⌘= | 放大或 App 對應操作 |
| Ctrl+-／0 | ⌘-／0 | 縮小／重設縮放 |

### 文字導覽與選取

| Windows 按鍵 | macOS 輸出 | 用途 |
| --- | --- | --- |
| Ctrl+←／→ | ⌥←／→ | 按單字移動 |
| Ctrl+Shift+←／→ | ⇧⌥←／→ | 按單字選取 |
| Home／End | ⌘←／→ | 行首／行尾 |
| Shift+Home／End | ⇧⌘←／→ | 選取至行首／行尾 |
| Ctrl+Home／End | ⌘↑／↓ | 文件開頭／結尾 |
| Ctrl+Shift+Home／End | ⇧⌘↑／↓ | 選取至文件開頭／結尾 |
| Ctrl+Backspace／Delete | ⌥Backspace／Delete | 刪除前／後一個單字 |

「Windows 文字游標」控制這組導覽規則，關閉後保留原鍵。一般表加上 Ctrl 文字導覽共 29 組既有規則，另有 4 組 Home／End 擴充。

### 瀏覽器

在辨識為瀏覽器的 Default macOS App，另套用 19 組規則：

| Windows 按鍵 | macOS 輸出 | 常見用途 |
| --- | --- | --- |
| Ctrl+T／Shift+T | ⌘T／⇧⌘T | 新增／重開已關閉分頁 |
| Ctrl+L | ⌘L | 網址列 |
| Ctrl+R／Shift+R | ⌘R／⇧⌘R | 重新整理／強制重新整理 |
| Ctrl+D | ⌘D | 加入書籤 |
| Ctrl+Shift+B | ⇧⌘B | 書籤列或瀏覽器對應操作 |
| Ctrl+Shift+N | ⇧⌘N | 私密視窗或瀏覽器對應操作 |
| Alt+←／→ | ⌘[／] | 上一頁／下一頁 |
| Ctrl+1–9 | ⌘1–9 | 選擇分頁，9 通常為最後分頁 |

範圍由 [瀏覽器與相容性模式表](Sources/BridgePlatform/Resources/compatibility-applications.json) 判定。Safari／YouTube 的無修飾鍵 `F`、`Escape`、滑鼠與原生 `⌃⌘F` 不套用這些規則。快捷鍵原始表見 [WindowsCompatibilityRules.swift](Sources/BridgeCore/WindowsCompatibilityRules.swift)。

## Finder 增強與右鍵路徑

先開啟「Finder 加強」。檔案操作檢查前景、session 與焦點，文字欄位或未知焦點採保守處理；Finder 增強關閉時，`Ctrl+X` 不套用一般剪下翻譯。

| Windows 按鍵 | Finder 行為 |
| --- | --- |
| Enter | 開啟選取項目（⌘O） |
| F2 | 改名（Return） |
| Ctrl+C／A／Z／Y | 複製／全選／復原／重做 |
| Ctrl+X | 先執行原生 Copy，記住待移動狀態 |
| Ctrl+V | 有有效待移動狀態時使用 Finder Move，否則一般貼上 |
| Delete 或 Fn+Backspace | 確認檔案選取時移到垃圾桶；文字／未知焦點保持前刪 |
| Shift+Delete | 永久刪除，需另開獨立開關且每次確認 |
| Backspace | 確認檔案焦點時前往上一層（⌘↑） |
| Alt+←／→ | 上一頁／下一頁 |
| Ctrl+N／W | 新視窗／關閉視窗 |
| Ctrl+Shift+N | 新增資料夾 |
| Ctrl+L | 前往資料夾（⇧⌘G） |

剪下狀態最多保留 **5 分鐘**；開啟資料夾、上一層或更換路徑仍可保留，剪貼簿變更、切換 App、暫停或狀態失效會取消。程式只記住剪貼簿版本／類型，搬移由 Finder 執行，不能以送出快捷鍵推定搬移成功。

內附 **Finder Sync 擴充功能**提供「複製目前資料夾路徑」、「複製選取項目完整路徑」及「顯示目前資料夾路徑 → 複製此路徑」。顯示子選單優先使用選取項目的完整 POSIX 路徑；只有點擊複製才寫入剪貼簿。需 App 正在執行、Finder 增強開啟且 macOS 已核准擴充功能。

HID 的「Finder 亮度增加鍵 → Enter」是獨立選項，預設關閉；只有同時開啟此選項、Finder 增強且前景為本機 Finder，才將支援的 consumer 亮度增加鍵轉成 Enter。

## 系統與視窗操作

| 按鍵 | 行為 | 開啟條件 |
| --- | --- | --- |
| Win+E | 開啟／啟用 Finder | Windows 快捷鍵、本機 Default macOS |
| Win+L | ⌃⌘Q 鎖定螢幕 | Windows 快捷鍵、本機 Default macOS |
| Ctrl+Shift+Esc | 開啟活動監視器 | Windows 快捷鍵、本機 Default macOS |
| Win+R | ⌘Space 開 Spotlight | 另開 Win+R |
| Win+I | 開啟系統設定 | 另開 Win+I |
| Win+Tab | ⌃↑ 開 Mission Control | 另開 Win+Tab |
| Alt+F4 | 按目前視窗的 Accessibility 關閉按鈕 | 另開 Alt+F4 |

Win+E/L/R/I/Tab 系統規則使用左側 Win，右側同組修飾鍵同時按住時不套用。Spotlight／Mission Control 使用系統預設快捷鍵，若改過系統設定，需自行確認。

Alt+F4 保留接收 App 的未儲存內容提示；找不到可用關閉按鈕會顯示原因，沒有 Command+W／Q fallback。自製 Alt+Tab 切換器已移除，使用 macOS 原生 `⌘Tab` 切 App、Command＋反引號（``⌘` ``）切同一 App 的視窗。HID 的 Option／Command 配置讓接管裝置的實體 Alt+Tab 使用原生切換器，仍須核對實際鍵位。

## 截圖與自動複製

「截圖自動複製」預設開啟。Windows 區域／全螢幕入口使用保留路由的原生系統事件，視窗擷取另確認目的端；原生 ⌘⇧3／⌘⇧4 存檔後由事件通知自動複製。來源不明與 Remote／VM／Game 情境保守穿透，同一事件不在 HID 與 EventTap 各翻譯一次。

| Windows 按鍵 | 截圖方式 |
| --- | --- |
| Win+Shift+S | 框選區域 |
| Alt+PrintScreen | 目前視窗 |
| Win+PrintScreen | 全螢幕存檔並複製 |
| PrintScreen | 預設框選，可改為傳統全螢幕複製 |

完成後存成 PNG 並複製至剪貼簿，可用 `⌘V` 貼上。存檔位置採 macOS 截圖設定，未設定或該目錄不可寫時回到桌面。EventTap 的 PrintScreen 對應 F13 位置，需核對鍵盤實際輸出。

`Escape` 取消不改剪貼簿。`Ctrl+Shift+S` 仍依 App 規則處理，原生 `⇧⌘3`／`⇧⌘4` 保持系統擷取流程，存檔後自動複製；直接送往 Preview／Mail 而未存檔的流程不支援自動複製。關閉功能會移除截圖攔截。

每次只接受一輪截圖，最多 120 秒；停用、暫停、後端／session／設定世代或 Secure Input 改變會取消舊工作，已完成存檔保留。圖片先檢查檔案、尺寸、像素與記憶體預算，再複製 PNG。權限、程序、磁碟、解碼與編碼失敗各有結果；反覆 Event Tap 停用會停止自動重試，可放開按鍵後重開功能重新檢查。

## MacBook 內建 Fn／Ctrl 交換

以原生 HID 鍵盤服務，只交換**本機實體內建鍵盤**的 Fn／Globe 與左 Ctrl，排除外接鍵盤及通用控制虛擬服務。MacBook 新安裝預設開啟，桌上型 Mac 預設關閉；舊設定有明確選擇時保留。

此功能不需 鍵盤處理／Driver。設定顯示已交換、等待鍵盤或衝突，並可「重新檢查鍵盤模式」。按鍵仍按住時延後變更或還原；其他工具占用 Fn／Ctrl 時保守停止，不覆蓋其映射。

關閉、全域暫停或正常退出會還原本程式的映射。寫入前保存私人還原 journal，強制結束後可於下次啟動復原，不能宣稱 SIGKILL 後立即還原。選 HID 時先還原原生交換，再由 背景鍵盤模式處理接管的內建鍵盤。Universal Control 兩個方向的實體 Ctrl／Fn、中文組字及睡眠恢復仍需實測。

## App Profiles 與遠端／通用控制

依前景 App 的 Bundle ID、可執行檔路徑及內建模式表判定。可從最近使用 App 指定 Profile，或選擇其他 `.app` 加入；變更立即儲存，移除自訂規則後回到內建判定。

| Profile | 用途 |
| --- | --- |
| Default macOS | 本機 Windows 快捷鍵翻譯，手動指定會覆寫內建保護 |
| Terminal | 保護 Ctrl+C／D／Z 等 shell 按鍵 |
| IDE | 保護編輯器、除錯器與內嵌終端機的原生 Ctrl |
| Remote Session | 遠端 Client 原樣通過，停止本機動作與輸入法切換 |
| Virtual Machine | VM 原樣通過，輸入捕捉由 VM 決定 |
| Game | 遊戲原樣通過，停止本機動作與輸入法切換 |
| Disabled | 不套用本機翻譯或輸入法守護 |

內建判定涵蓋 Terminal、iTerm2、Warp、Ghostty、Windows App／Microsoft Remote Desktop、Jump Desktop、Parsec、AnyDesk、RustDesk、VMware、Parallels、UTM、VS Code、Xcode、JetBrains 與 Steam 等，見 [App 清單](Sources/BridgePlatform/Resources/applications.json) 與 [相容性模式表](Sources/BridgePlatform/Resources/compatibility-applications.json)。清單存在表示有保護規則，不代表每個 Client 已完成驗收。

**Codex 新安裝預設 Default macOS，適用聊天與文字框。** 使用內建 Terminal 時改成 IDE 或移除 Codex 規則，保留 Ctrl+C 的 shell 意義。重啟不會重新加入已移除的規則，重新套用建議預設才會加入。

本版另有全域「遠端／通用控制輸入角色」：

| 角色 | 此端處理方式 |
| --- | --- |
| 本機／依 App 規則 | 使用上述本機判定 |
| 接收原始 Windows | 由此端翻譯收到的 Windows 按鍵 |
| 接收原生 Mac | 穿透已符合 Mac 語意的按鍵 |
| 來源已有 Bridge | 穿透，避免再次翻譯 |
| 傳送／Universal Control 來源 | 穿透，將翻譯交給另一端 |

這是**手動指定輸入語意**，不能自動辨識每筆事件的實體／遠端來源。兩端都安裝時需選一端翻譯；本版沒有逐遠端來源的自動路由。瀏覽器遠端分頁可用專用瀏覽器並指定 Remote Profile。Alt+Tab、Ctrl+Alt+Delete、全螢幕與剪貼簿轉送仍由遠端 Client 控制。

## 唯音與輸入法管理

唯音本體需另行安裝，Windows 快捷鍵與輸入法守護各自有開關。中文快捷鍵選項允許底層 ABC／U.S. 的輸入來源按實體鍵位翻譯，不讀組字內容，也不能可靠判斷選字狀態；有衝突時可關閉，只在 ABC／U.S. 使用翻譯。

| 功能 | 行為 |
| --- | --- |
| 輸入法守護 | 監聽來源通知，保留使用者從系統切換的來源，對程式自己的明確切換做有界重試 |
| 唯音繁體／ABC 按鈕 | 明確選擇來源，受暫停、session、受保護 App 與 Secure Input 約束 |
| 切換快捷鍵 | 獨立開關，啟用後切換唯音／ABC；註冊衝突時顯示狀態並嘗試保留原組合 |
| 暫停自動偵測 | 5／15／30 分鐘、1 小時或直到手動恢復，只暫停守護，Windows 快捷鍵照常 |
| 重新偵測／來源診斷 | 重新尋找來源，顯示來源 ID、切換結果與不可用原因 |
| 修正延遲 | 200–1200 ms，預設 400 ms，調整守護重試，不增加快捷鍵翻譯延遲 |
| 啟動等待 | 0–5000 ms，預設 1500 ms，等待登入時輸入法服務就緒 |
| 持久統計 | 自動修正、切回唯音、保留外部切換、失敗、Secure Input 等待、成功及恢復時間 |
| 記憶體診斷 | 開啟該頁或手動重新整理時量測 Resident／Physical footprint |

切換熱鍵有 `⌃⌥⌘Space`（預設）、`⌃⌥⇧Space`、`⌃⌘Space`、`⌥⌘Space` 四種組合。守護與熱鍵新安裝皆關閉。

重新啟用、恢復偵測、重新偵測、喚醒及重啟採用當前來源，不強制切回唯音。偵測暫停保存絕對截止時間，重啟、更新或睡眠不重新倒數。首次使用會一次性匯入舊唯音助手的六個統計欄位，不匯入舊設定或啟動舊 App；近期恢復紀錄最多 20 筆。

## 輸入後端與背景元件

| 項目 | EventTap（相容備援） | 裝置 HID（新安裝預設） |
| --- | --- | --- |
| 一般／瀏覽器／Finder／截圖入口 | 有 | 有，由同一 App 的前景與背景模式分工 |
| 可靠逐實體裝置識別與接管 | 無，使用所有鍵盤 | 依範圍與安全 descriptor 擷取 |
| Option／Command 裝置配置 | 不更改全域修飾鍵 | 對接管裝置依 Win 配置處理 |
| MacBook Fn／Ctrl | 獨立原生鍵盤映射 | 背景鍵盤模式處理接管的內建鍵盤 |
| consumer 亮度增加 → Enter | 無 | Finder 的獨立選用功能 |
| 安裝 鍵盤處理／Driver | 不需要 | 需要管理員安裝及 macOS 核准 |

HID 可選「所有支援的鍵盤」或「內建／Apple VID 1452、PID 834」。本版支援可完整轉送的 keyboard／相對 mouse descriptor 與標準複合服務；虛擬、multitouch、絕對座標或未知／不完整描述保持原生，最多 16 個服務。EventTap 選內建限定範圍時會停止翻譯，因其不能可靠辨識來源裝置。

完整單一 App 自動準備鍵盤處理與官方 VirtualHID 8.6.0；使用者只需依權限頁核准。Helper／Driver Ready 與接管數表示執行狀態，仍不等於實體鍵盤已驗收。共用 Driver 更新只接受已核對的版本與回復套件，未知版本停止；不移除其他工具正在共用的服務。

後端交接先等背景鍵盤模式停止擷取回覆，逾時保留新後端停用。受保護情境、Secure Input、session 不可用、失聯或 Driver 停滯會停止／釋放擷取，回到本機等待實體按鍵放開再接管；HID 不對同一按鍵再啟動一套 EventTap 翻譯。

更新以 staging、checksum／簽章／版本／controller pin 驗證後切換；一般失敗嘗試回復 App/runtime/pin/服務，最多保留兩份 App 備份。中止時保留私人復原 journal，下次執行安裝器先復原；共用 Driver 與 DriverKit activation 的副作用仍需實測。

停止可用選單列暫停／結束，App 無回應時可使用開發者停止腳本；內含 `UninstallBackend.sh` 移除本工具背景模式與 launchd 註冊，保留 App、使用者設定、備份與共用官方 Driver；Driver 移除依原廠流程處理。見 [HID 安裝指南](Resources/Installer/READ-ME-FIRST.md) 與 [HID 架構](Docs/HIDIntegration.md)。

## 授權、登入、暫停與恢復

權限頁平鋪七項：裝置控制與按鍵輸出、WindowsMacBridge 單一輸入監控、螢幕錄製、登入啟動、Finder 擴充、Driver 核准及截圖資料夾存取。每項只有「開啟設定」，程式會先提出對應要求；返回前景及手動「重新檢查」時確認原生結果，真正取得才顯示綠勾。開過設定、安裝完成或要求送出不能當成通過。

登入啟動使用原生登入項目，可能需系統核准。截圖功能會註冊登入項目，關閉時只移除由此功能新增的註冊，建議先將 App 放在 `/Applications`。

- **全域暫停**：選單列提供 5／15 分鐘、1 小時或直到 App 重啟，停止快捷鍵、截圖、Finder、Fn／Ctrl 與輸入法工作。
- **恢復／重啟引擎**：取消暫停與手動穿透，重新檢查並嘗試啟動。
- **緊急穿透**：右 Option+P 切換；Control+Option+Command+P 緊急暫停。HID 在 Remote／VM／Game 原生鍵流不攔截這些熱鍵，請用選單列暫停／結束。
- **安全恢復**：Secure Input、鎖屏、睡眠、session 變動或未知修飾鍵狀態期間保守停止，恢復時等待所有按鍵放開，不嘗試繞過安全輸入。
- **狀態圖示**：雙向箭頭表示 Windows Mode 啟用，雙直線表示暫停／停用；實際翻譯狀態看目前 App、Profile 與後端。

## 診斷與隱私

診斷頁提供版本／Build、UTC 編譯時間、Git revision、原始碼狀態與 Bundle ID，並可複製版本資訊；也顯示目前 App/Profile、後端、Secure Input、Finder、Fn／Ctrl、截圖結果、事件計數與最近規則。

「5 分鐘診斷」預設關閉，最多 128 筆規則 ID、App 與處理時間只存在記憶體，關閉時清除。HID 提供計數與最近命中規則；最大時間僅量測引擎 callback，不能當作完整 OS／App／遠端延遲或長期效能保證。

內建命令列診斷入口：

```sh
/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --version
/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --self-check
/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --diagnose-permissions
/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --diagnose-input-sources
/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge --diagnose-backend
```

`--self-check` 檢查內附模式表與 Finder 擴充版本，不啟動 Event Tap 或擷取。CLI 權限檢查可能使用啟動 Terminal 的 TCC 身分，執行中 App 的授權頁才是該 App 的判定依據。

`scripts/monitor-runtime.py` 是另行執行的唯讀量測工具，記錄 App 存活、PID、版本、累積 CPU、同 PID 區間 CPU、RSS 與定期 Physical footprint，可另選 Finder 擴充或系統總量，不自動啟動、停止或更新 App。範例（10 分鐘）：

```sh
python3 scripts/monitor-runtime.py --duration-seconds 600 --interval-seconds 60 \
  --footprint-every 5 --phase idle --output /tmp/WindowsMacBridge-runtime.csv
```

鍵盤事件留在本機，不網路上傳，不保存普通打字、密碼或 OTP，不讀既有剪貼簿 payload。Finder 只用剪貼簿版本／類型，以及有界 AX role／parent 與檔案 URL metadata 確認焦點，沒有文件文字或路徑歷史。右鍵複製由使用者明確觸發，截圖僅處理本次新產生的圖片。日誌在 `~/Library/Logs/WindowsMacBridge/`，守護日誌最多兩個約 512 KiB 檔案。

## 建置與測試

需要 macOS 與 Swift 6 工具鏈。主 App 無第三方 Swift 套件；內含 HID 使用固定 checksum 的官方 VirtualHID SDK。腳本可從 Git clone 或無 `.git` 的來源 ZIP 建置；ZIP 記錄 `archive` source state，可用合法十六進位 `SOURCE_REVISION` 指定來源版本。

```sh
# 核心與平台測試
bash scripts/test.sh
bash scripts/test.sh -c release
python3 -m unittest discover -s Tests/InstallerTests -v
python3 -m unittest discover -s Tests/MonitoringTests -v

# 建置 App 與一般 DMG
bash scripts/build-app.sh
bash scripts/package-app-dmg.sh

# 封裝含鍵盤處理及 Driver 安裝的單一 App 與 DMG
bash scripts/package-single-app.sh
bash scripts/package-app-dmg.sh
```

建置輸出在 `~/Library/Caches/WindowsMacBridge`，`build/` 保留輸出指標，下載包在 `build/download/`。App 只打包 allowlist 的 resource bundle；Finder extension Release 預設 `-O`，可用 `FINDER_RELEASE_OPTIMIZATION=-Osize` 比較。建置及封裝不安裝或啟動 Driver。

GitHub Actions 對 PR 與 `main` 執行 macOS 測試、Release 回歸、安裝器及量測工具測試，並建置 App、DMG 與 HID 整合包。CI 通過表示該次自動檢查成功，不代表 Release 已發布或實機相容性完成。

## 架構、限制與相關文件

`BridgeCore` 負責純規則、修飾鍵與按鍵帳本、Finder／截圖／輸入法 policy；`BridgePlatform` 負責 macOS API、EventTap、HID client、設定、截圖與動作；`InputSourceCore`／`InputSourceSupport` 負責輸入來源；主 App 負責選單列與設定，Finder Sync 負責右鍵路徑。

輸入 callback 只處理有界狀態及查表，AX、圖片、檔案、程序啟動與 UI 工作在 callback 外。HID 帳本最多 16 裝置／256 press slots、動作 inbox 16 筆、診斷 log 128 筆／64 KiB，保留 neutral recovery、session validation、heartbeat lease 與失聯釋放。

EventTap 沒有可靠逐裝置識別，HID 有 descriptor 覆蓋限制。ANSI／ISO／JIS、Bluetooth、consumer 服務、Caps Lock／LED、中文組字、跨機與遠端、撤權、強制結束、睡眠恢復、端到端延遲及長期資源使用仍須依情境驗收。離線測試、綠色 CI 與 Ready 狀態不等於實體輸入路徑已確認。

| 文件 | 內容 |
| --- | --- |
| [使用指南](Resources/UserGuide.md) | 完整操作、預設值、權限與移除 |
| [實機驗收](Resources/AcceptanceGuide.md) | 鍵盤、Finder、截圖、輸入法、遠端與恢復 |
| [權限修復紀錄](Docs/SimplePermissions-2026-10-02.md) | 最新安裝、分頁與原生權限確認 |
| [八類功能複查](Docs/ReviewerAudit-2026-10-02.md) | 程式修復、支援缺口與實機方法 |
| [四方向修復](Docs/FourAreaRepair-2026-10-02.md) | 前批測試證據與未完成验收 |
| [架構](Docs/Architecture.md) | 輸入層次與安全邊界 |
| [HID 整合](Docs/HIDIntegration.md) | 單一 App、XPC、Driver、擷取與安裝 |
| [HID 安裝指南](Resources/Installer/READ-ME-FIRST.md) | 核准、停止、復原與移除 |
| [專案整合](Docs/ProjectIntegration.md) | 唯音助手與快捷鍵整合 |
| [Karabiner 對照](Docs/KarabinerReplacement.md) | 規則遷移與後端限制 |
| [驗證說明](Docs/Validation.md) | 自動測試與人工驗收分界 |

沿用部分唯音助手實作並保留 [VChewingGuard MIT 授權](Resources/Licenses/VChewingGuard.txt)。VirtualHID SDK／Driver 與相依授權保留於 [第三方授權目錄](Resources/Licenses/VirtualHID) 及 [來源清單](Resources/Licenses/VirtualHID/sources.json)。
