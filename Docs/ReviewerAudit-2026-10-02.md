# WindowsMacBridge：八類功能 production code 複查

日期：2026-10-02。範圍依本輪使用者指示：以 reviewer 找問題、修改實作、提供測試方法，**不執行測試、語法檢查、benchmark、建置、封裝或實機驗證**。本報告的「確認」指程式路徑可確認，並非已執行重現；修正均尚待驗證。保留原工作目錄修改，沒有安裝 App 或修改系統授權／Driver。

既有 0.5.17 / build 29 ZIP、DMG 不含本輪修正；舊報告的測試數字不能套用到最新來源。

## 已確認錯誤與已修改實作

| ID／優先度 | 問題與影響 | 修改位置與處理 |
|---|---|---|
| R1／P1 | 解除安裝無条件 bootout VirtualHID daemon。即使 launchd label 屬於 Bridge，daemon 仍可能正服務其他工具；移除 Bridge 會中斷它們。 | `Resources/Installer/UninstallBackend.sh`：只停止與移除 Bridge helper；保留共用 daemon、Driver 及其 launchd 註冊。helper 若仍註冊則不刪除檔案。移除指南同步說明共用服務仍會執行。 |
| R2／P1 | InputEngine 的安全狀態轉換只比較 AX、Secure Input、session，漏掉獨立的 posting 權限。僅銷毀 tap 不會清掉舊動作／原生切換持鍵狀態。 | `Sources/BridgePlatform/InputEngine.swift`：posting 變化也 drain 舊輸出、invalidate processor／Remote frame 並推進 action epoch。已撤權時無法保證系統接受 release，仍需實機驗收。 |
| R3／P2 | Fn／Ctrl 還原以 source 為單位刪除映射；同一 source 同時含 Bridge 配對與其他工具新增目的鍵時，會把外部配對一併刪除。 | `Sources/BridgeCore/MacBookKeyboardMapping.swift`：只移除完全相同的 Bridge 配對；若該 source 尚有外部配對，不加回舊映射蓋過它。 |
| R4／P2 | 每次 foreground generation 變動都要求 Remote 全程序 discovery，快速換 App 會廢棄並重做 metadata／簽章工作。 | `Sources/BridgePlatform/RemoteInputAdapters.swift`、`Sources/WindowsMacBridge/BridgeController.swift`：程序 registry 不再依前景 generation 重建；保留啟用、程序啟動、手動 discovery、觀察新 PID 的查詢。目的端動作的 generation／frame 檢查仍由 router 保留。 |
| R5／P2 | Fn mapper refresh 即使 ownership 沒變仍重寫 journal，包含 fsync／F_FULLFSYNC；正常換 App 可重複同步磁碟。 | `Sources/BridgePlatform/MacBookKeyboardMapper.swift`：以 Journal 值比較最後成功保存內容，略過重複寫入；失敗不快取，ownership 改變仍須先保存才能改鍵盤。 |
| R6／P2 | 截圖 worker 原本只在整個 prepare 前後檢查取消；Pause／逾時後即使 decode 已結束，仍可能繼續進行 PNG 編碼。 | `Sources/BridgePlatform/ScreenshotManager.swift`：metadata、decode、PDF draw 與 encode 階段之間加入取消檢查；PNG consumer 在取消後停止接受新 chunk。不能強制中斷已進入系統 codec 的呼叫。 |
| R7／P2 | 原生截圖觀察沿用「可寫入目的地」fallback，可能監看錯誤資料夾；讀取既有原生截圖也錯誤要求父資料夾可寫，導致 diskFailure。 | 同上：分離原生截圖設定目錄與 Bridge 擷取的可寫 fallback；原生檔案不再要求父目錄可寫，檔案讀取失敗仍由準備流程處理。 |

## 資源開銷改善（未量測）

| ID | 可由程式確認的多餘工作 | 修改 |
|---|---|---|
| R8 | 原生 screenshot observer 為不支援副檔名／子資料夾／Bridge 自己產生的檔案也建立 metadata worker。 | `Sources/BridgePlatform/NativeScreenshotObserver.swift` 在排入工作前做純路徑過濾；保留 metadata 與 Apple screenshot 標記檢查，不增加 timer。相同截圖的重複 metadata 事件尚未全部消除。 |
| R9 | 每份快捷鍵查找表為 4,096 個 slot 配置完整 `ShortcutRule?`，大多數為空；每個 slot 都保留規則結構的空間。 | `Sources/BridgeCore/RuleEngine.swift` 改為 `UInt16` 索引表與緊密規則陣列。每份索引資料為 8,192 bytes，另加實際規則與陣列開銷；仍為直接索引查找，保留重複／越界輸入拒絕。這不是整個 App 記憶體的量測值。 |

## 八類覆蓋與尚存邊界

| 功能 | 本輪閱讀的主要 production 路徑 | 審查結論／限制 |
|---|---|---|
| 1. Windows 快捷鍵與持鍵 | KeyboardEventProcessor、RuleEngine、WindowsCompatibilityRules、InputEngine、RemoteSourceRouter、HIDBackendClient | 新增 R2、R9。processor 保留 down/up 配對與中斷 tombstone；EventTap 缺乏可靠實體 device ID，不能把 aggregate 模型當成兩把鍵盤已驗收。 |
| 2. HID／EventTap／UC／Remote | InputSources、DestinationSemanticPolicy、RemoteInputAdapters、RemoteSourceRouter、InputEngine、HIDDescriptorPolicy、helper DeviceCapture／HelperService | 新增 R4。新快捷鍵檢查 recipient，舊来源 token 可撤銷；未知來源及不支援 descriptor 保守不接管。但 PID 被隱藏、virtual HID 偽裝成硬體、多 peer 共用 producer 仍是支援缺口。 |
| 3. Finder／視窗 | ShortcutActionDispatcher、FinderActionPolicy、FinderCutState、WindowCloseExecutor、NativeAppSwitchLatch | 本轮未另確認可直接修改的錯誤。cut 以 clipboard changeCount＋Finder PID 授權移動；Delete 未知焦點不送丟垃圾桶，close 使用 focused-window AXPress。永久刪除仍須測確認期間焦點变化。未見自製 MRU／視窗列舉切換器的 production 路徑；保留的是原生切換持鍵配對。 |
| 4. 截圖／圖片 | ScreenshotManager、ScreenshotCaptureDriver、NativeScreenshotObserver、ScreenshotCaptureLifecycle、PDFImageBudget、ImageMemoryBudget | 新增 R6–R8。舊 token 不能通過最後 clipboard gate；PDF 有繼承 resources／內嵌圖／節點與尺寸預算，但 parser、色彩轉換與系統剪貼簿配置未有整體硬上限。 |
| 5. 權限／Driver／更新 | KeyboardPermissionRequest、HIDBackendClient、HelperService、InstallBackend.sh、DriverTransaction.sh、DriverProcessRunner.c、UninstallBackend.sh | 新增 R1、R2。GUI 使用真正 posting API；helper 檢查 console UID、簽章與 root pin。版本白名單／交易 journal／失敗回復不代表 OS 系統延伸功能核准及重開機已驗收。 |
| 6. Fn／Ctrl | MacBookKeyboardMapper、MacBookKeyboardMapping、PrivateMappingJournal、NativeMacBookKeyboardBackend | 新增 R3、R5。指定本機內建鍵盤、以 boot identity 保存 ownership；crash／force quit 後要靠再次啟動或重開機恢復，不能宣稱被殺當下即時復原。 |
| 7. 中文輸入／App 模式 | InputSourceCoordinator、GuardController、InputSourcePolicy、RuntimePolicy、BridgeController | 本輪未另確認新錯誤。host work 失效與 selectionAllowed 二次檢查存在；組字／選字語意仍需唯音與實際 App 驗收。Secure Input 重試採退避，沒有為本輪新增高頻 timer。 |
| 8. 效能／建置／封裝 | 上述 callback 路徑、BoundedDiagnosticLogger、Package.swift、build-app.sh、source-version.sh、LoginItemManager | 新增 R4–R6、R8–R9。log／action queue 有界，HID heartbeat 的租約用途保留。腳本有 archive fallback、Release 最佳化與明列資源；未執行 clone／ZIP build，不能寫成可建置已確認。 |

## 支援缺口

- UC／Remote 沒有共同的完整來源與目的 metadata；兩端 Bridge 不重複翻譯仍需逐 transport 證據。Karabiner 的實機表現不能代替這份實作的驗收。EventTap 無 device ID 時，不能完整還原兩把鍵盤同鍵同按的來源帳本。
- 原生 ⌘⇧3／⌘⇧4 自動複製依賴存檔事件與 Apple screenshot xattr；沒有存檔、事件丟失、檔案尚未寫完就被看見、特殊儲存 provider 等情境，仍非完整可靠的完成通知協定。Observer 在送出候選時就記錄 seen，首次處理失敗並沒有自動重試保證；本輪沒有以新增輪詢掩蓋此缺口。
- PDF 內容串流的解壓、系統 image codec／ICC 的內部分配，不受 raster 預算完全約束；取消也不能打斷同步系統呼叫。若需要嚴格 CPU／記憶體／逾時隔離，需獨立可終止 worker process，這輪沒有新增此架構。
- 共用 Driver 的未知版本仍拒絕修改；解除安裝刻意留下共用服務，不能同時承諾完全移除 daemon 與零第三方中斷。這是共用所有權限制，不應用程序名稱或瞬間 client 數猜測「可以刪」。

## 需要實機驗證／交給使用者的測試方法

以下均**尚未執行**。先使用下一份包含本輪來源的候選包；涉及刪除僅用可丟棄資料。完整跨機步驟見 `Resources/TwoMacAcceptance.md`，其舊版本號只是範本。

1. **持鍵／權限（R2）**：Ctrl+C 後保持 Ctrl，按 Tab、再加 Shift；交換放開順序。分别插入 Pause、App 切換、posting 撤銷／恢復、Secure Input、拔鍵盤、換 backend。全部放開後新按鍵不得帶入舊 Command，舊動作不得恢復。兩把鍵盤分別測同側 Ctrl／同字母。
2. **共用服務（R1）**：在專用驗收環境讓另一 client 使用 VirtualHID，再移除 Bridge helper。另一 client 的輸入與共用 daemon PID 應維持；Bridge helper 的 launchd 註冊與檔案應移除。另用 fixture 模擬 helper bootout 失敗且仍註冊，應拒絕刪檔；pending recovery 應在停止服務之前就拒絕。
3. **Fn ownership（R3、R5）**：用可注入 backend 放入「Bridge Fn→Ctrl」及同 source 的另一目的鍵；還原只能移除 Bridge 配對，不得刪掉另一配對。journal 未變時連續 refresh 不應重寫；變更或前次保存失敗仍須寫入。實機再測正常退出、force quit 後重啟、外接鍵盤與第三方映射並存。
4. **Remote CPU（R4）**：保持 producer 不變，快速切換兩個普通本機 App；以 Instruments 觀察不應每次都出現全程序 discovery／簽章查詢。再啟動新 Remote host、改 profile、退出並重開 producer，確認仍能更新且舊動作 token 無效。這裡只記錄需觀察的路徑，不預設 CPU 百分比。
5. **截圖（R6–R8）**：四種 Windows 截圖與 ⌘⇧3／⌘⇧4 各測一次；取消、撤權、不可寫目錄、壞圖要分類正確。大 TIFF／PDF decode 時 Pause／換 session，旧結果不能覆寫；取消後不得再進下一個 encode 階段。可讀而父資料夾不可寫的既有原生 screenshot 應可複製。大量非圖片檔案事件不應建立圖片 metadata worker。
6. **查找表（R9）**：對每份規則逐一比較 input→output／action；檢查無規則組合回 nil、重複 chord 拋錯、key 128／未知 modifier 被拒絕，再確認 Ctrl+C→Ctrl+Tab 與瀏覽器分頁未變。若量測，分開記錄 rule table 配置與整個 App footprint。
7. **Finder／原生切換／中文**：Ctrl+X 後換資料夾再 Ctrl+V；檔名編輯與未知 AX 焦點分別按 Delete。Alt+F4 測未儲存視窗；亮度鍵在一般 App 不能變 Enter。⌘Tab／同 App 視窗切換保持原生；唯音組字、選字與 Terminal Ctrl+C 不被搶走。
8. **兩台 Mac**：先兩台都不開 Bridge 確認 UC；再依次測僅目的端開、兩端都開，最後反向。來源 Terminal→目的 TextEdit 必須複製；目的 Terminal 必須保留 Ctrl+C 中斷。用 Ctrl+Z 每次只退一個可確認步驟檢查重複動作，不能只靠剪貼簿相同判定。來源 Finder 檔案與視窗不得被動作。
9. **整體資源／封裝**：若日後驗收，分開量測 GUI、helper、screencapture、系統剪貼簿的 footprint 與生命週期；單純 RSS 相加不是整體實體記憶體。由乾淨 Git clone 與不含 .git 的 ZIP 各建置 Release，再驗收資源、登入啟動、停止／移除。Driver 核准、重開機、中斷回復使用獨立實機驗收，不拿 fixture 代替。
