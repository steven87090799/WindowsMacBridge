# Windows 快捷鍵正式環境審查

2026-11-05，審查基準為已合併 PR #26 的主分支 `1b4c120`，修正候選版為 **1.0.3 build 69**。本輪已修正可重現的快捷鍵與遠端輸入問題，Debug 與 Release 各 584 項測試通過。正式使用判定仍須完成下列本機及遠端實機驗收；目前沒有把 build 69 安裝到日常環境。

## 已修正的問題

| 優先度 | 觸發方式與原有結果 | build 69 行為 |
| --- | --- | --- |
| P1 | 遠端通道即使已完成所有按鍵釋放，仍永久佔用固定 16 個名額；第 17 個來源或事件來源狀態無法再翻譯。 | 空位用完後重用最久未使用且已完全釋放的通道；保留仍按住的按鍵、修飾鍵、切換器與釋放記錄。只撤銷被重用通道的延遲工作，不撤銷同一來源的其他通道。 |
| P2 | Finder Ctrl+Home／End 直接送出 Command+上／下鍵，在檔案列表可能開啟父資料夾或所選項目；Shift 組合有相同問題。 | 在回呼外確認文字焦點。文字欄位使用內容開頭／結尾與選取；其他焦點送出原生 Home／End，保留 Shift。文字導覽關閉時原樣通過。 |
| P2 | Firefox 沿用一般瀏覽器 F11、搜尋與 Shift+F5 對應，且缺少部分 Firefox 指令。 | F11 使用 Command+Shift+F；Ctrl+K／E 使用 Command+K；Ctrl+F5 強制重新載入；Shift+F5 保留效能分析。補上首頁、書籤管理、清除資料與開發工具的原生對應。[Firefox 官方快捷鍵](https://support.mozilla.org/en-US/kb/keyboard-shortcuts-perform-firefox-tasks-quickly) |
| P2 | Edge Ctrl+J 沿用 Chrome 的 Command+Shift+J。 | Edge 正式、Beta、Dev、Canary 使用 Command+Option+L 開啟下載；Chrome 保留自己的 Command+Shift+J。[Microsoft 官方快捷鍵](https://support.microsoft.com/en-us/edge/keyboard-shortcuts-in-microsoft-edge) |
| P2 | Opera Ctrl+H／J／U 沿用 Chrome 的歷史、下載、原始碼對應；Vivaldi Ctrl+Shift+D 被當成將所有分頁加入書籤。 | Opera 使用 Command+Shift+H、Command+J、Command+U；Vivaldi 使用 Command+Option+L 開啟下載面板。[Opera 官方快捷鍵](https://help.opera.com/en/latest/shortcuts/)、[Vivaldi 下載面板](https://help.vivaldi.com/desktop/panels/downloads/) |
| P2 | Terminal 設定與規則預覽文字仍說「沒有選取時 Ctrl+C 中斷」，與現行程式不同。 | 介面、指南與預覽統一說明 Ctrl+C 一律複製、Ctrl+Shift+C 才中斷。截圖驗收文字也改為目前的 App 內圖片預覽。 |

瀏覽器的預設快捷鍵依官方說明核對；使用者自行修改的 App 快捷鍵，仍需依實際選單設定驗收。新增 Chrome Ctrl+Shift+I 對應到原生開發工具，與既有 F12 共用相同輸出。[Chrome 官方快捷鍵](https://support.google.com/chrome/answer/157179?hl=en)

## 審查範圍

| 功能範圍 | 已檢查的程式與測試契約 |
| --- | --- |
| Ctrl 與文字操作 | C／X／V／A、Insert 別名、復原／重做、儲存、列印、文字格式、分頁、字詞與段落導覽；Terminal、IDE、Finder 及瀏覽器的分流。 |
| Win 與 Alt | Option 作為 Win、Command 作為 Alt；Win+E／L、選用 R／I／Tab、Alt+Tab／F4、瀏覽紀錄與截圖組合；左右修飾鍵與原生 Command 保護。 |
| 滑鼠 | Ctrl 點選、多選、Ctrl+Shift、Finder 複製拖曳與替身；先放 Ctrl、來源／接收 App 改變、暫停、session 中斷與已產生事件標記。 |
| 輸入生命週期 | down／repeat／up、重疊快捷鍵、持鍵切 App、Pause、Secure Input、權限、休眠／session、來源撤銷、非同步操作取消及有界資料結構。 |
| 遠端與裝置 | 接收端來源辨識、Google 自動／原始 Windows 語意、Apple 簽章與系統路徑、UC 目的端證據、Remote Windows／VM 原樣通過；EventTap／HID 與本機 Fn／Ctrl 範圍隔離。 |
| Finder 與截圖 | 剪下移動意圖、過期及取消、文字焦點、永久刪除的 Finder 確認、截圖來源與舊工作隔離、記憶體預算、圖片預覽清理。 |
| 安裝與背景執行 | 權限與後端交接、共用 Driver 保護、安裝中斷與回滾、當機復原及次數限制、關閉介面的資源釋放。 |

沒有增加鍵盤回呼中的程序查詢、簽章查詢或 AX 掃描；既有 mailbox 必定讀取最新 revision 的契約保留。來源未知時仍可讓第一個輸入原樣通過，後續再完成非同步辨識。

## 自動驗證結果

環境為 Apple Silicon、macOS 27.0、Swift 6.4、macOS 27 SDK；App 最低支援版本維持 macOS 14。

| 檢查 | 結果 |
| --- | --- |
| 主分支原有測試 | 576 項通過；仍由新增案例重現覆蓋缺口。 |
| 修正前新增回歸 | 六項測試均能重現問題，共 47 筆失敗記錄；這不是 47 個獨立缺陷。 |
| 修正後 Debug | 584 項通過，含獨立程序的截圖與診斷記憶體回歸。 |
| 修正後 Release | 584 項通過，含相同的獨立記憶體回歸。 |
| 安裝與回滾 | 66 項通過。 |
| 當機與正常退出復原 | 13 項通過。 |
| 資源監測 | 6 項通過。 |
| Release App | build 69 建置、自我檢查、必要資源及簽章驗證通過；GUI 未載入 OCR 框架。 |
| 介面離線檢查 | 產生 20 張合成介面圖；已查看最小設定視窗及規則預覽。306 個視窗／檢視弱引用全部釋放，保留 0 個。 |
| 合成修飾鍵循環 | 600 萬個事件完成，所有按鍵釋放後的狀態檢查通過。 |
| 相同遠端路由設定重複更新 | 180 萬次更新完成，涵蓋 0／1／16 個已建立來源；量測程序最大 footprint 增量為 245760 bytes。 |

新增的八項回歸涵蓋 Finder 文件邊界、不同瀏覽器預設、一般／HID／Google 遠端的 down／up 配對、停用功能與 guest 保護，以及 32 個來源、單一來源的 32 種事件狀態與 16 路同時持鍵。既有快捷鍵涵蓋測試也擴充到修正後的瀏覽器組合。這些新增案例只使用合成事件，不向日常 App 輸出按鍵。

主要回歸位置：

- [WindowsProductionRegressionTests.swift](../Tests/BridgeCoreTests/WindowsProductionRegressionTests.swift)
- [ShortcutCoverageTests.swift](../Tests/BridgeCoreTests/ShortcutCoverageTests.swift)
- [ContextualNavigationTests.swift](../Tests/BridgePlatformTests/ContextualNavigationTests.swift)

合成效能量測不代表硬體輸入延遲、整個 App 的閒置耗電或長時間實機穩定性。建置中仍有既有 CLT 搜尋路徑與供應商 SDK 精度警告；本輪沒有新增編譯錯誤。

## 正式使用前的實機驗收

以下每列各自記錄兩端 macOS／App 版本、輸入裝置、實體按鍵、來源與目的 App、首次／重連結果。build 64 的歷史實測不替代 build 69 的驗收。

| 路徑 | 必須驗證的重點 | 本次狀態 |
| --- | --- | --- |
| 本機外接鍵盤 | 左右 Ctrl、複製貼上、文字導覽、Finder 多選與拖曳、各瀏覽器、App 切換、暫停與喚醒。 | 待實機 |
| MacBook 內建鍵盤 | 僅本機開啟 Fn／左 Ctrl 交換；實體 Fn+C／X／V／A、原左 Ctrl、外接鍵盤不受交換。 | 待實機 |
| Windows 經 Google 遠端桌面控制 Mac | 實體 Ctrl、多選與拖曳、快捷鍵；接收端自動與原始 Windows 模式分開測；首次及重連第一下／第二下。 | 待實機 |
| Apple 螢幕共享兩方向 | Mac mini 使用外接 Ctrl；MacBook 僅在已啟用交換時使用內建 Fn。兩方向各測 C／V／Z、重連與原生 Command。 | 待實機 |
| 通用控制兩方向 | 目的端執行操作、來源端不得誤觸；持鍵跨邊緣、斷線與恢復後無殘留修飾鍵。 | 待實機 |
| Remote Windows 與 VM | guest 接收原始 Ctrl／Alt／Win；關閉或切回本機時沒有舊按鍵殘留。 | 待實機 |
| 選配 HID 與權限 | 實體裝置接管、共用 Driver、停止與連線中斷、授權撤銷、安裝／更新回滾。 | 待實機 |
| 截圖與長時間使用 | 三種 Windows 截圖、取消及貼上、圖片預覽、權限、連續操作、長時間閒置與休眠喚醒。 | 待實機 |

操作細節使用 [AcceptanceGuide.md](../Resources/AcceptanceGuide.md)、[TwoMacAcceptance.md](../Resources/TwoMacAcceptance.md) 與 [Apple 螢幕共享事故及驗收紀錄](ScreenSharingVNC-2026-10-24.md)。只使用可丟棄的 TextEdit 文字、檔案與測試圖片；快捷鍵路由與共享剪貼簿運送分開驗收。

## 交付狀態

build 69 是審查候選版，採 ad hoc 簽章；不標示為已公證正式版。本輪沒有更動系統權限、Driver、Karabiner、Fn／Ctrl 映射或已安裝 App；開始時核對日常環境為 **1.0.3 build 67**。本機與各條遠端路徑驗收完成前，不能將自動測試通過改寫成「正式環境已確認沒有問題」。
