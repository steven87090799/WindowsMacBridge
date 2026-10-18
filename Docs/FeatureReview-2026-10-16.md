# WindowsMacBridge：功能、正確性與效能複查

日期：2026-10-16，Asia/Taipei。已完成本輪發現問題的修復，並加入快捷鍵規則預覽、遠端校準介面與截圖文字擷取。自動驗證通過；目前沒有尚未修復、已確認可重現的本輪程式問題。這不代表任何裝置與情境都零缺陷，也不能由有限測試證明整個系統效能已達絕對最佳。

## 基準與覆蓋範圍

開始修改前及收尾時都先更新遠端資訊；最後 `git fetch origin --prune` 後，HEAD 與 `origin/main` 都是 `949fc1f4d005b84f969d98e12e4a37249bd147f8`。工作分支為 `codex/complete-audit-repairs-20261015`，本機尚未提交／推送。使用者指定的 `origin/fix/final-production-hardening-20261003` 仍是這個基準的祖先。

**HID 一秒期限問題已包含於基準，沒有重新列為未修復問題。** 本輪未修改 `Tools/HIDBackend/Sources`。既有未確認放鍵保護、ConnectionLease、Secure Input、來源撤銷與持鍵配對仍保留，並納入完整回歸。

本輪延續 [main 逐檔審查](/Users/steven/Documents/ChatGPT/我/Docs/CurrentMainAudit-2026-10-15.md) 與 [R01–R06 修復報告](/Users/steven/Documents/ChatGPT/我/Docs/RepairReport-2026-10-15.md)。最終內容清單涵蓋 271 個檔案：256 個原有追蹤檔加 15 個新增正式碼／測試／工具；其中 229 個與 main 的逐檔雜湊相同，27 個原有檔修改。沿用未變更檔的先前審查證據，本輪重新核對修改內容、新增檔與整合路徑，沒有把雜湊比對說成再次逐行人工閱讀所有未變更檔。

產物與歷史 log、下載的第三方 SDK、Git 內部資料、新產生的報告本身不算正式碼逐檔覆蓋。先前 main 的審查清單與雜湊保持原樣。[最終來源清單](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/tested-source-snapshot.json) 與 [最終驗證清單](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/final-verification.json) 對應本次已測工作目錄。

## 三項新增功能

| 功能 | 完成的行為 | 重要界線 |
|---|---|---|
| 快捷鍵規則預覽 | 選 App、預覽模式、本機／遠端來源與模擬總開關；列出 18 組常用快捷鍵，並可自選按鍵及 Ctrl／Option／Command／Shift／Fn。透過實際 processor、router 與截圖政策計算結果，未啟用前也能查看。 | 合成輸入，不發送真實按鍵；以左側修飾鍵與送入 Mac 的事件為基準。實際權限、焦點、實體鍵盤與遠端軟體前處理仍需現場確認。 |
| 遠端校準介面 | 顯示已觀察輸入與僅偵測到軟體的差異；選定來源後，明確開始一次 Ctrl+C 校準，60 秒內取得結果，確認後保存。可取消、還原校準前設定或恢復自動判斷。 | 綁定來源 identity／PID／birth／工作有效性。未知來源保守通過。離線、受保護場景、政策改變或到期都保留原設定；儲存失敗不顯示成功。 |
| 截圖文字擷取 | 設定頁與選單可框選畫面，以 Apple Vision 辨識繁中／英文並複製純文字。顯示擷取／辨識狀態、可取消；一般圖片截圖維持原流程。 | 與圖片共用單一工作。只在操作時啟動獨立辨識程序；空白、失敗、取消、權限撤銷或工作失效都不覆蓋剪貼簿。不記錄辨識文字。 |

OCR 使用 [Apple Vision 文字辨識 API](https://developer.apple.com/documentation/vision/recognizing-text-in-images)。語言由執行環境支援清單過濾；停用語言校正，以保留文字與程式碼的字面內容。未加入生成式 AI，也不要求 Apple Intelligence 才能 OCR。

主要實作：[ShortcutPreview](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/ShortcutPreview.swift)、[預覽頁](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/ShortcutPreviewView.swift)、[校準協調器](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/RemoteCalibrationCoordinator.swift)、[校準頁](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/RemoteCalibrationView.swift)、[Vision worker](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/ScreenshotTextRecognition.swift)、[程序管理](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/ScreenshotTextWorkerClient.swift)。

## 本輪確認並修復的問題

| 問題 | 修復與回歸重點 |
|---|---|
| 原校準會因正常切換前景而取消，無法順利轉到文字 App 測試 | 允許一般本機 App 間切換；受保護目的地與其他輸入政策改變仍取消。測試覆蓋切換、來源替換、逾時與撤銷。 |
| 原校準取得結果後直接儲存，缺少可檢查、取消與還原的完整操作 | 加入 waiting → review → saved 狀態及明確確認，保存上一筆設定以供還原；若後續已另行修改，還原不覆蓋新設定。 |
| 遠端偏好達容量或寫入失敗時可能沒有明確成功／失敗契約 | 保存回傳 Bool、顯示容量與寫入失敗，成功才標記已套用。失敗保留既有有效設定。 |
| 設定更新可接受讀取端會拒絕的 schemaVersion | 寫入驗證與讀取支援版本一致，拒絕不支援版本並保留可讀的舊偏好。 |
| 相同遠端 snapshot／configuration 反覆更新重建每個來源的設定 | 在完整相等時直接返回。配置或來源有變仍執行原本更新與放鍵；未快取或跳過每個事件的安全檢查。 |
| 新 OCR 需要避免常駐模型、失控輸出、孤兒程序與 EOF 重複回呼 | 獨立子程序、有限 JSON 回覆、30 秒期限、取消時 TERM／必要時 2 秒後 KILL；EOF 移除讀取 handler。主程序退出通知及啟動前後父 PID 檢查，避免孤兒辨識。 |

新 OCR 的資源邊界：輸入沿用最大 64 MiB、36M pixels、144 MiB 解碼預算，並計入 16-bit 圖片深度；辨識縮圖最長邊 2560、最多 4M pixels；結果上限 1000 行／64 KiB UTF-8，超限回報失敗。這些是輸入與輸出邊界，**不是 Vision 整體模型記憶體的硬上限**。

父程序將影像寫入私人 0600 檔案描述符，寫入像素前已 unlink，再將描述符作為 worker stdin；避免檔名被替換，也避免程序崩潰留下有名稱的 OCR 輸入影像。擷取暫存與 worker 輸入的所有權、取消及失效結果均有測試。

前輪 R01–R06 與 V01 修復仍在，包括退出前 Fn／Ctrl 還原確認、總開關契約、journal crash gap、偏好容量、受保護復原暫存及程序辨識。完整測試入口保留獨立記憶體測試，沒有放寬 128 MiB 增量斷言或刪除 60 次重複處理。

## 效能與記憶體證據

環境：Apple M2、16 GiB、macOS 27.0（26A428）、Swift 6.4。本節為指定工作負載的有限量測，不是整個 App 或整台 Mac 的效能保證。

### 重複來源更新 A/B

Release、同一離線測量工具，先暖機並以各來源送入／放開合成按鍵，再量測 200,000 次相同更新；每個情境三輪，以下取 CPU 時間中位數。工具與 router 的 SHA 保存在原始結果。

| 來源數 | 修改前 CPU 秒 | 修改後 CPU 秒 |
|---|---:|---:|
| 0 | 0.031890 | 0.005415 |
| 1 | 0.044235 | 0.005413 |
| 16 | 0.334107 | 0.004734 |

16 來源的這個特定重複更新工作減少約 98.6% CPU 時間；不能換算成全 App 或真實鍵盤延遲改善 98.6%。持鍵不被相同更新打斷、配置改變仍正確放鍵、來源撤銷等有回歸覆蓋。[修改前](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/routing-before.json)／[修改後](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/routing-after.json)。

### 預覽

91,800 組合成快捷鍵評估（含暖機），計時區間 90,000 組，CPU 約 0.123 秒。每批 18 組的平均延遲分位數 p50／p95／p99 約 24.16／26.82／27.93 微秒；不是單次呼叫的尾延遲。量測前後工具 physical footprint 增加 16 KiB。介面僅在設定或自選按鍵變動時重新計算，不持續輪詢。[原始結果](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/preview-performance.json)。

### 真實 Vision、生成圖片

三次辨識同一張生成的 `SCREEN TEXT 123` PNG，均正確取得文字：24.149 秒、0.280 秒、0.266 秒。第一次較慢符合模型／系統資產暖機的可能性，但這份測量沒有隔離各項啟動成本，也不代表其他裝置一定相同。30 秒期限內成功；更忙碌或更慢的裝置可能逾時，介面會回報且保留剪貼簿。

測量父程序 physical footprint 從 5.24 MiB 到 5.67 MiB（增加約 0.44 MiB），三輪合計父程序 CPU 約 0.0045 秒；子程序最高 RSS 約 230.64 MiB。這是離線呼叫器的增量，不是完整 GUI 的啟動記憶體。worker 每輪已退出，但系統仍可能保留共享 Vision 資產，不能宣稱全機快取立即清零。[量測結果](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/ocr-performance.json)。

另以本次 App worker 實測兩種父程序退出情況：exec 前父程序已退出、工作進行中父程序退出。兩者皆結束且沒有輸出辨識結果；觀察退出時間約 33 ms／3 ms。僅操作測試自行建立的 PID，未結束使用者的 App。[整合證據](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/ocr-parent-exit.json)。

### 實際系統狀態的界線

唯讀快照確認 `/Applications/WindowsMacBridge.app` 仍為 **build 47** 且正在執行；候選 build 50 沒有啟動常駐 GUI。全機 memory pressure 查詢約 49% free、swap 約 1.3 GiB；這些是全機與既有使用歷程的數據，不能歸因於新程式，也不構成記憶體洩漏或應清除 swap 的證據。[系統快照](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/system-context.json)。

未為量測改動使用者的按鍵映射、權限、服務或其他 App；未清除系統快取。候選 GUI 的長時間 idle／真實輸入資源曲線仍屬安裝後驗收工作。

## 最終驗證

| 項目 | 結果與證據 |
|---|---|
| 完整 Debug | **465 項通過**：42 VirtualHID、14 SourceSupport、40 SourceCore、202 Platform、166 Core、1 個獨立記憶體測試。[log](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/debug-full.log) |
| 完整 Release | **同 465 項通過**。[log](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/release-full.log) |
| InstallerTests | **62 項通過**，421.714 秒；私人測試副本與 fixture。[log](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/installer-full.log) |
| MonitoringTests | **6 項通過**。[log](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/monitoring-full.log) |
| Release App | **0.6.0 build 50** 建置成功；來源標示 `949fc1f4… (modified)`，build UTC `2026-10-16T02:15:12Z`。[build log](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/app-build.log) |
| 離線自檢與簽章 | App registry 自檢、HID codec 自檢及 `codesign --verify --deep --strict` 通過。沒有開啟 event tap、連接 HID service 或擷取裝置。[App](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/app-self-check.log)／[HID](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/hid-self-check.log) |
| 介面 | 5 張生成狀態的離線渲染；已檢查新頁、最小尺寸與 OCR idle／busy。沒有建立真實控制器或要求 TCC。[render log](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/visual-checks-final.log) |
| 差異與腳本 | `git diff --check`、修改 shell 的 `bash -n` 通過；HIDBackend/Sources 與基準無差異。 |

Swift 每種組態較上一輪 436 項增加 29 項；相同測試針對性重跑不重複累計。程序 fixture 包含格式／大小錯誤、非零退出、逾時、SIGTERM 被忽略的取消升級、繼承 stdout 寫端不阻塞；截圖路徑包含取消、暫停、session 失效、權限撤銷及一般圖片不呼叫 OCR。

這些是本機驗證，並非新 commit 的遠端 CI。建置仍有既有 CLT search-path／vendor 警告，未宣稱零警告。簽章為本機 ad-hoc／development 驗證，沒有 Apple 公證。

介面證據：[規則預覽](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/visual-checks-final/shortcut-rules.png)、[最小尺寸](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/visual-checks-final/shortcut-rules-minimum.png)、[遠端校準](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/visual-checks-final/remote-calibration.png)、[文字擷取](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/visual-checks-final/screenshot-text.png)、[辨識中](/Users/steven/Documents/ChatGPT/我/build/feature-review-20261016/visual-checks-final/screenshot-text-busy.png)。

## 尚待實機驗收與交付狀態

程式與使用說明已完成。最低 macOS 14 支援保留。本機候選 build 50 位於 [WindowsMacBridge.app](/Users/steven/Library/Caches/WindowsMacBridge/e046ae762ceb/Artifacts/WindowsMacBridge.app)，尚未取代 `/Applications` 的 build 47，也未發佈、安裝 Driver 或變更系統授權。

仍需實機確認：真實螢幕擷取授權與多螢幕框選、真實遠端來源與跨 Mac／UC 校準、物理鍵盤／HID 放鍵交接、AppKit 持鍵退出與取消、候選 GUI 的長時間 CPU／記憶體。這些不能由合成 fixture 或離線畫面推定已驗收。

使用者追加的 Apple AI API 調查與功能優先順序已整理在 [Apple AI 功能建議](/Users/steven/Documents/ChatGPT/我/Docs/AppleAI-FeatureIdeas-2026-10-16.md)。目前建議先做「OCR 後翻譯／摘要面板」與「中文描述設定 → 規則預覽」；本輪沒有把生成式模型加入鍵盤事件路徑。
