# WindowsMacBridge 最新 main 全專案審查報告

> **後續修復：** 使用者隨後指示「那先修復」。修復內容與驗證見 [RepairReport-2026-10-15](/Users/steven/Documents/ChatGPT/我/Docs/RepairReport-2026-10-15.md)。本文件及逐檔 SHA 清單保留 `949fc1f4` **修復前**的審查證據；下文「仍存在／未修改」均指該次審查時點。

**第二次複核版：2026-10-15。** 本版新增反例／對照驗證、效能與維護優化，以及新功能建議；第 8–10 節記錄新增證據、現有功能與尚未實作的差異。六項現存問題沒有因建議或待驗證推論而增加計數。

審查日期：2026-10-15（Asia/Taipei）。本次先同步遠端，再審查 **0.6.0 build 49**：`origin/main` 與工作分支 `codex/complete-audit-repairs-20261015` 均為 **`949fc1f4d005b84f969d98e12e4a37249bd147f8`**。遠端同步紀錄為 2026-10-15 13:22:08 +08:00。

**確認仍存在 6 項程式／診斷缺陷：P2 四項、P3 兩項；另記錄 1 項已知的並行測試可靠性問題。沒有確認現存 P0／P1。** 這不是無缺陷保證，也不是 HID、Driver、TCC 或跨 Mac 的實機驗收。

先前 [build 46 審查](/Users/steven/Documents/ChatGPT/我/Docs/FullProjectAudit-2026-10-15.md) 未先同步到最新 main，錯把已修復的 HID 一秒期限及輸入法 pending 問題列為現存問題。這是審查基準錯誤，**不是這兩項修復在 build 49 再次失效**。本報告取代該份報告的現行結論；舊報告保留為特定 commit 的歷史紀錄。

依使用者「先完整審查」的指示，本輪只產生報告、逐檔清單與隔離驗證證據，未修改正式碼或測試，也未安裝 App、操作使用中的鍵盤、變更授權或啟用 Driver。

## 1. 同步、版本與審查範圍

| 項目 | 核對結果 |
|---|---|
| 本次基準 | main `949fc1f4d005b84f969d98e12e4a37249bd147f8`，build 49 |
| 使用者指定參考分支 | `fix/final-production-hardening-20261003`，本機與 origin 均為 `1d36990631e6c82b275fa02e90742ee75fa06275` |
| 修復是否已進 main | 已以 Git ancestry 核對；該分支經 PR #13／`a356dbe` 合併，之後 PR #14 加入截圖與 Terminal／IDE 剪貼簿修正 |
| 參考審查文件 | [FinalProductionReview revision 3](/Users/steven/Documents/ChatGPT/我/Docs/FinalProductionReview-2026-10-03.md)，含 revision 1–3 的重開、修復及未驗收項目 |
| 審查環境 | macOS 27.0（26A428）、arm64、Apple Swift 6.4（swiftlang-6.4.0.34.1）、Command Line Tools |
| 檔案基準 | 256 個 tracked files；252 個文字檔，共 28,254 行；4 個二進位圖示 |

覆蓋方式是**先前逐行審查＋檔案雜湊核對＋最新差異與整合呼叫鏈複查**。179 檔與先前已審查內容 SHA-256 完全相同，沿用該部分審查；59 個既有檔案重讀變更行及相關上下文，18 個新增檔案完整閱讀。77 個變更／新增檔案的完整檔案行數合計 14,173，這個數字不是新增行數，也不冒稱 256 檔全部重新從頭閱讀一次。

| 審查方式 | 檔案 | 文字行數 | 說明 |
|---|---:|---:|---|
| 第一方程式、測試、腳本、CI、設定的逐行審查 | 211 | 21,822 | 依上述雜湊沿用／差異複查方法，追查實際 production 接線 |
| 結構化 fixture | 1 | 3,654 | 沿用完整解析與 78 個 manipulator 的條件、輸出、去重核對；雜湊相同 |
| 文件／指南一致性 | 29 | 2,523 | 對照目前行為、歷史基準與驗收聲明 |
| 授權文字清單 | 11 | 255 | 存在性與打包清單核對，不當作法律意見或第三方實作審計 |
| 二進位圖示 | 4 | 不適用 | 格式／尺寸核對；雜湊與先前相同 |

逐檔路徑、完整行數、SHA-256、審查方式與沿用來源見 [256 檔覆蓋清單](/Users/steven/Documents/ChatGPT/我/Docs/CurrentMainAudit-2026-10-15-files.json)。統計不包含本輪新增報告、ignored 證據、`.git`、建置產物、下載的第三方 SDK 與產生的 override headers。已安裝 App 的內容及實機狀態另需驗證。

## 2. 舊問題逐項對帳

| build 46 報告 ID | 最新 main 狀態 | 本輪依據 |
|---|---|---|
| F01：HID 一秒後停送 pointing | **已修復，移出現存缺陷** | WMB-01 修復已合併；[flushPointing:464](/Users/steven/Documents/ChatGPT/我/Tools/HIDBackend/Sources/HIDRuntime/DeviceCapture.swift:464) 使用 capture phase／設定／session／readiness，沒有舊 heartbeat age 條件 |
| F02：正常退出未完成 Fn／Ctrl 還原 | **仍存在 → R01** | 以本次 main 編譯模組重新執行持鍵 stop fixture |
| F03：Secure Input 中途驗證留下 pending | **已修復，移出現存缺陷** | WMB-28；[verification:864](/Users/steven/Documents/ChatGPT/我/Sources/InputSourceSupport/GuardController.swift:864) 早退前清除 pending；本次 harness 輸出 pending=false |
| F04：獨立開關受核心快捷鍵牽動 | **仍存在 → R02** | 最新 RuntimePolicy 模組及 host／UI 呼叫鏈核對 |
| F05：journal 發布窗口刪除快照 | **仍存在 → R03** | 最新安裝器的私人 fixture，在 journal hardlink 發布後注入 SIGTERM |
| F06：設定可寫不可讀 | **仍存在 → R04** | 最新 SettingsStore 模組，隔離 UserDefaults suite 寫入及重新載入 |
| F07：復原失敗累積當次 payload | **仍存在 → R05** | 最新安裝器 fixture，失敗重試兩次，副本 1→2→3 |
| F08：監控漏認重新啟動參數 | **仍存在 → R06** | 最新 app_pids 所產生的正式 regex 與 RelaunchApp.sh 參數比對 |

HID 目前仍有「持鍵時一秒安全檢查」，有未完成輸出時會提早至 0.6 秒；這是 WMB-52 的輸出／持鍵失聯保護，**不是舊版 configure 超過一秒便停止轉送 pointing 的期限**。不能因程式仍出現「一秒」就重新開立 F01。複合鍵盤／指標的實際轉送及釋放仍未在本輪接管硬體驗證。

輸入法 harness 證明原本的 pending latch 已清除；不把這個結果擴張為每種 Secure Input 情境都成功切換輸入來源。[本輪 guard 輸出](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/guard-repro.log)

## 3. 最新 main 確認缺陷

P2 是功能正確性或復原可靠性問題；P3 是較低影響的資源／診斷問題。以下六項均對照本輪精確 commit，不沿用舊版已修復問題的嚴重度。

| ID | 級別 | 問題 | 主要位置 |
|---|---|---|---|
| R01 | P2 | 持鍵時正常退出，Fn／Ctrl 映射還原仍待處理，觀察已停止 | [MacBookKeyboardMapper.swift:167](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/MacBookKeyboardMapper.swift:167) |
| R02 | P2 | 關閉 Windows 核心快捷鍵，連帶停用仍顯示開啟的截圖及 Fn 模式 | [RuntimePolicy.swift:45](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/RuntimePolicy.swift:45) |
| R03 | P2 | journal 發布成功至 switched 旗標更新之間中斷，留下失去快照的 journal | [InstallBackend.sh:375](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:375) |
| R04 | P2 | 儲存不限制 encoded bytes，重開卻拒絕超過 64 KiB 的設定 | [SettingsStore.swift:117](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:117) |
| R05 | P3 | 保留舊復原快照時，也洩漏當次新建的 payload scratch | [InstallBackend.sh:218](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:218) |
| R06 | P3 | 官方 --permission-relaunch 啟動後，監控將運作中的 App 記為 down | [monitor-runtime.py:31](/Users/steven/Documents/ChatGPT/我/scripts/monitor-runtime.py:31) |

### R01：正常退出沒有完成持鍵時的原生映射還原

**觸發：** 本機 MacBook Fn／Ctrl 模式已套用；正常退出時尚有按鍵按住。`stop()` 先 `stopObserving()`，再執行一次 `refresh()`。`restore()` 第 180 行因非 neutral 拒絕寫回，保留 journal 及 restorePending，但之後沒有觀察／重試機會。[AppMain:54](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/AppMain.swift:54) 只有 `applicationWillTerminate → controller.stop()`；[Controller:283](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:283) 先移除 mapper callback 再停 mapper／engine，沒有等待還原完成的終止協調。

**本輪重現：** 連結最新 Debug 的正式 BridgePlatform／BridgeCore 模組，假內建鍵盤先成功交換，再設 `keysNeutral=false` 呼叫 stop。結果 `swapped=true`、`observing=false`、`restorePending=true`、`awaitingNeutral=true`，journal 仍存在；將 keysNeutral 改回 true 後沒有新的 refresh，映射仍未還原。[platform-repro.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/platform-repro.log)

**影響與界線：** 正常退出路徑無法保證完成指南承諾的還原。這是實際 mapper 狀態機與 App 終止接線的證據；本輪沒有改動真實鍵盤映射，不宣稱已完成實機復現。保留 journal 本身是必要的復原設計，不應為關閉警告而刪除它或在持鍵時強行覆寫。

**修復／驗收：** 增加正常終止協調，在 neutral 且驗證還原完成前保留必要觀察；採有界等待與明確結果處理。覆蓋 Cmd+Q 持鍵、放鍵後完成還原、寫回失敗及保留外部映射；再在內建鍵盤實測。強制終止／crash 的下次啟動復原與本項分開。

### R02：獨立功能開關實際依賴核心快捷鍵

**觸發：** 關閉「Windows 核心快捷鍵」，但保持「Windows 快捷截圖」或「MacBook 鍵盤模式」開啟。[SettingsView:178](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/SettingsView.swift:178) 將三者呈現為獨立開關；[Controller:527](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:527) 卻將 settings.enabled 放進 shortcutEnabled。`permitsPhysicalNormalization` 與 `permitsScreenshots` 都經 permitsInput／permitsShortcuts 再依賴 shortcutEnabled；[native mapper:455](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:455) 與 [screenshot config:594](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:594) 使用這些結果。

**本輪重現：** session／權限正常，`shortcutEnabled=false`、`screenshotEnabled=true`，最新 Core 回傳 `permitsScreenshots=false` 及 `permitsPhysicalNormalization=false`。[policy-repro.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/policy-repro.log)

**影響：** 顯示開啟的功能實際停止，不能只選用截圖或原生 Fn 交換。這是 UI 與政策相依關係不一致；若產品意圖就是總開關，應調整名稱、說明及子開關狀態，而非保持目前的獨立功能呈現。

**複核分類：** 已確認的是開關行為與畫面／說明不一致，不能單憑這份重現判定 engine 應採哪種產品語意。因此保留為功能契約問題；將底層改成獨立開關只是可選修法，不是已經證實的唯一正確實作。

**修復／驗收：** 明確分開共用的 pause／Secure Input／session／權限／ownership 安全條件與各功能旗標，或一致呈現總開關。補 host 整合測試，涵蓋 core off＋screenshot on／Fn on，以及授權撤銷、HID release pending 等安全條件，不能為獨立功能而繞過安全 gate。

### R03：journal 已發布、快照卻仍被當成可刪的暫存

**觸發：** [InstallBackend:375](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:375) 的 `/bin/ln` 已發布 `.install-recovery`，第 376–378 行尚需移除暫存 journal、清空變數及 sync，第 379 行才設定 `bridge_switched=1`。此窗口退出時，[finish:150](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:150) 因 switched=0 不清 journal，第 158 行卻刪除它指向的 stage。

**本輪重現：** 沿用最新版 InstallerTests 的私人目錄與命令 stubs，只在其一次性腳本副本的 ln 後插入 SIGTERM。結果退出碼 -15、journal 存在、快照不存在；舊 App／helper 保持原內容。下一次安裝回傳 1，報 `Invalid recovery snapshot.`。[backend-repro.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/backend-repro.log)

**影響：** 後續 recovery 無法前進；[UninstallBackend:8](/Users/steven/Documents/ChatGPT/我/Resources/Installer/UninstallBackend.sh:8) 也會因 pending journal 拒絕操作。此窗口在 App／Driver 切換前，不將它誇大成當下已毀損舊 App。這與 WMB-55 的 **App bundle publish／retirement 身份競態**不同：WMB-55 的修復仍保留，本項是 recovery journal 與 stage 的清理責任窗口。

**修復／驗收：** 追蹤本程序成功發布 journal 的所有權，讓發布後每個退出點都保留有效快照或安全撤除自己發布的 journal；不能只依賴較晚的 switched 旗標。測 ln 後、rm 後、sync 前後中斷／命令失敗，以及並行安裝；不得直接刪除真實使用者的復原 journal 來掩蓋問題。

### R04：SettingsStore 可以成功寫出下一次拒絕讀取的設定

**觸發：** 設定中的 overrides 增長至 encoded JSON 超過 65,536 bytes。[read:95](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:95) 有 64 KiB 限制；[update:117](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:117) 只檢查 next.valid，編碼後直接保存；[valid:36](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:36) 不限制 overrides 的數量或編碼大小。

**本輪重現：** UUID 隔離的 UserDefaults suite 加入 2,000 個 overrides，寫出 135,452 bytes，valid=true、saveError=nil；重新建構 Store 後 enabled=false、overrides=0，顯示讀取失敗。[platform-repro.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/platform-repro.log)

**影響與界線：** App 接受的設定在重開後變成停用的安全預設。讀取失敗仍保留原始 blob，並非立即刪除所有設定；使用者後續儲存安全預設才可能覆寫原資料。fixture 結束後已清除隔離 suite，未碰使用者設定。

**修復／驗收：** 寫入與讀取共用 encoded-byte 上限，拒絕超限時保留前一份有效設定及清楚錯誤。測上限前後、成功儲存的 reload round-trip、儲存失敗的原資料保留及非 ASCII bundle ID／設定值大小。

### R05：失敗復原每重試一次多留一份新 payload

**觸發：** 安裝器第 13 行建立當次 stage，第 243 行複製 payload，再處理既有 interrupted transaction。[recovery:218](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:218) 設 preserve_stage=1，將全域 stage 換成舊快照；新 stage 只存在 local bridge_new_stage。之後 Driver phase 驗證或 rollback 失敗，EXIT 第 139–141 行直接保留退出，未回收當次新 stage。

**本輪重現：** 私人 fixture 先產生 interrupted-install snapshot，再令 driver.phase 無效；兩次重試皆失敗，stage／payload 副本由 1→2→3，原復原快照持續保留。[backend-repro.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/backend-repro.log)

**影響：** 持續重試會累積完整 App／Driver payload 的暫存磁碟用量。保護舊快照正確；本項要求回收的是當次未使用 scratch，不是刪除有可能包含待復原或隔離物件的舊快照。

**修復／驗收：** 分別管理當次 scratch 與受保護 recovery snapshot。所有失敗路徑都核對新 scratch 已回收、舊快照及 quarantine 完整保留；成功復原／重試後也核對目錄數。

### R06：監控不接受官方權限重啟參數

**觸發：** [RelaunchApp:8](/Users/steven/Documents/ChatGPT/我/Resources/Installer/RelaunchApp.sh:8) 以 `open -n … --args --permission-relaunch` 啟動。[app_pids:31](/Users/steven/Documents/ChatGPT/我/scripts/monitor-runtime.py:31) 對主 App 的 regex 要求 executable path 後立刻結束，只有 Finder extension 接受空格後的參數。

**本輪重現：** 擷取正式 app_pids 交給 pgrep 的 pattern；純路徑匹配 true，加上正式 `--permission-relaunch` 參數後匹配 false。[backend-repro.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/backend-repro.log)

**影響與界線：** 由工具自身執行的權限重啟會使診斷漏採 CPU／RSS 並標為 down；不影響 App 本身功能。這是 regex／啟動契約證據，本輪未為此重新啟動使用者 App。

**修復／驗收：** 主 App 也接受「完整 executable＋空白／結尾」邊界，保持精確路徑，避免匹配同名前綴或子工具。測無參數、正式重啟參數、其他合法參數及相似路徑的排除。

## 4. 既有修復的複查結果

除了 F01／F03，亦對照指定分支 revision 2／3 的修正與目前 production 接線，避免重新開立已修復問題或破壞其安全語義。

| 既有項目 | 本輪複查 |
|---|---|
| WMB-51：HID release 證據 | 保留每個 lease 的 stop 狀態；只有 ACK、neverOwned 或 helper 確定退出可證明 release。timeout／transportLost 仍鎖定 releaseUnconfirmed；不能為解除 UI gate 把 XPC 斷線當釋放證據。42 項 VirtualHID／175 項 Platform 測試包含對應回歸。 |
| WMB-52 revision 3：held safety | keyboard／pointing button／outstanding output 都計入；HeldSafetyTimer 可提早已排定的期限，避免持續沿用較晚的一秒檢查。不是永久 idle heartbeat。 |
| WMB-53：Finder positive evidence | 檔案內容需要 AX 正面證據；文字欄位、sidebar、toolbar、sheet、unknown 不推定為 folder。hierarchy fixture 通過；真實 Finder AX tree 仍需驗收。 |
| WMB-54：截圖單次 bounded read | 同一個 nofollow／nonblock fd 檢查普通檔、上限、讀取及重查，ImageIO／PDF 使用同一份 immutable Data；未重新開啟來源 path 或使用 mapped file。並行記憶體測試問題另列 V01。 |
| WMB-55 revision 3：App publish／retirement | exclusive rename、固定 fd、實際移動物件身份檢查與 durable retirement.unconfirmed 均保留。外來物件與 quarantine 不得在 cleanup／後續 recovery 被刪除。R03、R05 不要求弱化這些保護。 |
| WMB-56：每鍵工作量 | permission key-edge reads 有一秒快取，lifecycle 強制重查；Secure Input 仍每事件檢查；remote expiry 依 deadline 變更才重排。不是宣稱所有權限撤銷已實機量測。 |
| WMB-57：輸入法等待 | Secure Input backoff 保留單次有界 pass，無永久每 30 秒輪詢；對應 intent tests 通過。 |
| PR #14：截圖 recipient | 全螢幕／選區接受有依據的本機接收 PID，允許 Control Center 面板接收；active-window 仍要求 foreground ownership；缺少本機接收 PID 不在來源 Mac 擷取。 |
| PR #14：Terminal／IDE | Ctrl+C/V/A/X 在本機採剪貼簿語義，Terminal Ctrl+Shift+C 中斷；遠端 Windows／VM 保留 Ctrl。這是已合併的功能變更，不當作舊有 Unix 保護規則的回歸。 |

## 5. 本輪驗證與 V01

| 檢查 | 本輪結果 | 證據 |
|---|---|---|
| Debug，預設並行 | **FAIL：428 項中 1 項失敗**，ScreenshotBoundedReadTests 的 process-wide footprint 門檻；其餘通過 | [debug-parallel.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/debug-parallel.log) |
| Debug，相同已編譯測試序列執行 | **428/428 PASS** | [debug-serial.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/debug-serial.log) |
| Release，預設並行 | **FAIL：428 項中同一項失敗** | [release-parallel.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/release-parallel.log) |
| Release，相同已編譯測試序列執行 | **428/428 PASS** | [release-serial.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/release-serial.log) |
| Installer／root bootstrap／rollback／source-version | **54/54 PASS**，355.054 秒 | [installer.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/installer.log) |
| Monitoring | **5/5 PASS** | [monitoring.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/monitoring.log) |
| 六項現存問題與 pending 關閉核對 | 本次 main 的正式編譯模組／私人安裝 fixture／正式 regex 重現；不碰真實使用者環境 | [證據說明](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/README.md) |
| 靜態解析 | 18 個 bash、10 個 Python、6 個 plist、4 個 JSON 均通過解析／語法檢查 | [static-checks.json](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/static-checks.json) |
| Release App／簽章／離線自查 | **PASS**：0.6.0 (49)，revision 949fc1f；App deep strict／FinderSync strict 簽章驗證及兩項自查均 exit 0 | [build.log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/build.log)、[app-verification.json](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/app-verification.json) |
| 本次精確 main 的 Hosted CI | `test-and-package`、`hid-installer-package` 均 success；2026-10-12 完成，本輪以 API 重新查證，未觸發新 run | [GitHub run 38243213045](https://github.com/steven87090799/WindowsMacBridge/actions/runs/38243213045)、[API snapshot](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/hosted-checks.json) |

Swift 的不同測試數為 157 Core＋175 Platform＋40 InputSourceCore＋14 InputSourceSupport＋42 VirtualHID＝428。加上 Python 54＋5，**487 項不同的既有測試在序列 Swift 配置下通過**；不將 Debug／Release 重跑重複加總，也不將本機預設並行執行寫成 PASS。

App 的 source metadata 顯示 `modified`，原因是 source-version.sh 將本輪四個未追蹤的報告／manifest 也納入工作區狀態；不是正式碼變更。已逐檔確認 256 個 tracked files 與 HEAD 及審查 manifest 完全相同。`--self-check` 載入 28 筆 registry；`--hid-self-check` 回報 codec OK、driver=10800、protocol=7，兩者均未開啟 EventTap、連接服務或擷取／輸出裝置事件。

**V01（既有驗證可靠性問題，與六項產品缺陷分開計數）：** [ScreenshotBoundedReadTests:124](/Users/steven/Documents/ChatGPT/我/Tests/BridgePlatformTests/ScreenshotBoundedReadTests.swift:124) 在同一個測試程序內採樣整體 phys_footprint，再套用 +128 MiB 門檻，無法隔離其他 suite 的並行配置。本次 Debug／Release 並行皆在第 137 行失敗，同一組 binary 的完整序列執行皆通過。指定分支 revision 3 第 139 行已記錄同樣現象，所以不稱為這次新增的產品 memory leak。

這些結果也不能證明所有記憶體問題均不存在。本輪未定位其他並行 suite 的配置峰值；應將此量測隔離至獨立程序或明確受控的測試階段，同時保留真正能抓出逐次成長的門檻。不要單純放寬 +128 MiB、刪除斷言或以重跑到綠燈替代處理。CI 目前仍使用預設並行路徑；遠端成功與本機失敗需要同時保留。

本機 log 亦保留 CLT 可選 framework／library search path、SDK Asio 轉型及測試 weak var 等警告；本輪未據此確認新的 runtime 缺陷。未執行本次 commit 的 ASan／TSan、本機無 .git archive 完整建置或本機 ZIP／DMG 打包，不沿用舊審查的結果冒稱本輪已執行；Hosted CI 成功另以精確 commit 記錄。

## 6. 模組、文件與待驗收事項

| 區域 | 本輪結論與界線 |
|---|---|
| Core／規則／modifier ledger | 逐行基準及最新剪貼簿／來源語義差異已核對；現有模型測試通過。實際兩把鍵盤的 aggregate flags 順序仍需實測。 |
| EventTap／Remote | source session、PID／身份、generation／work gate、unknown passthrough 與有界 inbox 保留；UC／各 remote transport 不能從純模型結果升格為實機 Verified。 |
| AX／Finder | positive focus evidence 與動作取消／前景檢查保留；真實 Finder 的 rename、cut→move、native delete confirmation、文字鍵順序仍未驗收。 |
| 截圖／圖片／PDF | single-flight、取消、來源／接收者 gate、encoded／decoded／pixel／PDF budget 保留。程式 buffer 預算不是 App＋screencapture＋WindowServer＋clipboard 的整體 RAM 上限。 |
| HID／VirtualHID／XPC | 舊一秒 pointing 問題已修復；release 證據、held safety、controller per-message authentication、pin 單 fd 讀取與 teardown 修正保留；實體 seize／DriverKit 成功與釋放時間仍需驗收。 |
| Fn 原生映射 | 僅內建鍵盤、保存原映射、外部衝突保護保留；R01 是正常退出尚有持鍵的收尾缺口。 |
| 輸入法 | 原 pending latch 已修復；guard-off、不自動改變明確英文選擇、有界 retry／backoff 與 lifecycle cancellation 已核對；實際唯音組字／選字仍需驗收。 |
| 安裝／移除／設定／監控 | 共享 Driver 保護、套件 hash／簽章、sealed root copy、受保護 rollback 保留；R03–R06 需另外修復，fixture 不能代替管理員安裝。 |

指定舊報告 WMB-32–38 仍有未解或設計／硬體限制，本輪不將它們假裝修好，也不把尚未驗證的風險混入六項已確認缺陷：

| 既有項目 | 本輪保留的狀態／需要的證據 |
|---|---|
| WMB-32：descriptor array sub-elements | 是否拒絕真實支援鍵盤仍未確認；需有授權的 USB／Bluetooth／內建鍵盤 element enumeration，不能盲目放寬 seize 條件。 |
| WMB-33：單一裝置永遠不 neutral | 目前有全域 capture gate；需多裝置實測及 per-device lifecycle 設計評估。 |
| WMB-34：VirtualHID warning sticky fault | 需官方 Driver 實際 warning／reconnect 證據；不新增 root 無限重建迴圈。 |
| WMB-35：Finder rename 文字鍵順序 | 非同步 AX 派送有重排／丟棄風險；需真實 rename 焦點／輸入時序驗證。 |
| WMB-36：截圖 tap 在 main run loop | 程式事實仍在，是否造成可感知延遲需量測；沒有延遲數據不宣稱已證明效能回歸。 |
| WMB-37：virtual-device exclusion | 仍依 vendor／name，且 0x16c0 篩選涵蓋 V-USB；需真實裝置辨識資料，避免誤抓虛擬裝置或誤排外接鍵盤。 |
| WMB-38：發行簽章／共享 Driver 所有權 | ad-hoc 不能建立發行者身份；Developer ID／公證及共享 Driver ownership 是發行設計工作，不能靠本機測試補足。 |

文件／可達性另有以下問題，與程式缺陷分開：

1. [HID backend README:6](/Users/steven/Documents/ChatGPT/我/Tools/HIDBackend/README.md:6) 仍使用不存在的 build-hid-helper／package-hid-release 腳本、舊 BridgeHIDHelper 路徑及 --serve 入口。舊報告已承認此項，不當作新發現。
2. 追蹤中的 Markdown 有 10 處本地引用目標在本工作區不存在，均位於 [PreReleaseRepair 歷史報告](/Users/steven/Documents/ChatGPT/我/Docs/PreReleaseRepair-2026-09-30.md:121)：包含未隨 Git 保存的 build 證據及已移除入口。應保留歷史基準並標註可取得性。
3. `NativeScreenshotObserver` 與其測試不是目前 production capture lifecycle 的主要接線；observer 測試不能當作實際全套快捷截圖驗收。
4. VirtualHID／HIDLifecycle 模型測試不等於直接執行完整 DeviceCapture adapter；仍需可注入 transport／clock 的 adapter 邊界及實機驗收。
5. Inert FinderSync 仍打包、installer logs 未修剪、uninstall 保留備份／Licenses、未打包的 legacy commands，沿用舊報告的低風險維護清單，不為清理而擅刪使用者內容。

## 7. 修復順序與交付狀態

1. R01、R03：先處理正常退出的映射還原，以及 journal 發布後每個退出點的可恢復性。
2. R02、R04：統一 UI／功能 gate 契約，及成功儲存必能重新讀取的設定邊界。
3. R05、R06：分清 scratch／recovery 所有權並回收新暫存；修正監控啟動參數匹配。
4. V01 與文件：隔離 process-wide 記憶體量測、保留門檻，修正仍在指向舊架構的開發說明。
5. 修復後針對各重現補回歸，再完成相應 Debug／Release 與必要實機情境；不得修改既有安全語義來取得綠燈。

目前交付是**最新 main 的完整審查與舊問題對帳；六項確認缺陷尚未修改**。詳細本機 log／harness 位於 [current-audit-20261015](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015)，該目錄為 ignored；Docs 報告與 manifest 可另行納入版本控制。結論只適用於上方精確 commit／雜湊，不代表使用者已安裝版本或所有硬體情境。

## 8. 第二次複核：對照驗證與排除誤報

2026-10-15 13:55:48 +08:00 再次 fetch，HEAD／origin/main 仍相同。此輪重讀 App 啟停／設定接線、InputEngine、截圖完整 lifecycle、Remote registry／router、原生映射、輸入法 guard、HID runtime／C++ 輸出及安裝交易的關鍵路徑；其餘沿用第 1 節的逐檔審查與雜湊證據。這是同一份完整專案審查的反向複核，沒有把工具掃描或雜湊相同比喻為重新人工閱讀所有行。

| 核對項目 | 對照結果 | 結論 |
|---|---|---|
| R01 正常退出 | neutral stop 可還原；held stop 不還原且停止觀察；放鍵後明確 refresh 又可還原 | 缺口在正常終止協調，不是映射還原演算法全壞 |
| R02 開關 | core on＋screenshot on 可用；core off 阻擋截圖與 normalization；pause／撤銷 listening 同樣正確阻擋 | 行為已確認，修法須一致定義總開關或獨立功能；共用安全 gate 保留 |
| R03 journal | ln 前注入命令失敗：無殘留；ln 後、旗標前失敗：journal 有、snapshot 無；旗標後失敗：正確回復／清理 | 再次確認精確窗口，並非所有安裝失敗都無法復原；此輪不只依賴 signal 注入 |
| R04 設定 | 小設定 round-trip 通過；大設定 135,478 bytes 寫入不報錯、reload 使用 fallback，原 blob 仍在 | 相同容量不對稱再次成立；本輪多一個小型規則，大小與首輪 135,452 bytes 不同 |
| 舊 HID 一秒期限 | 純 lifecycle 中 connectionLeaseValid=true、lastHeartbeat=0，在 now=1,000 開始，在 now=100,000 仍 capturing；移除 lease 才 release→close | 一秒 fallback 字樣仍可在模型找到，但 production adapter 使用 connection lease；不重新開立已修復問題 |
| 截圖舊工作疑點 | off／on 或 epoch 改變時 active slot 保留，舊工作完成前新 begin 回 nil；舊 token 不能清新 token | 「toggle 後立刻開始新工作，舊 completion 取消新 timeout」這個候選時序被現有 gate 阻擋；未列為缺陷 |
| V01 記憶體量測 | 同版 binary 單獨執行該項測試：1/1 PASS，1.440 秒 | 保留並行不穩定紀錄；沒有足夠證據稱產品 memory leak，也不宣稱已證明零洩漏 |
| 遠端校準 | 明確 arm 後僅指定 PID 的一次 Ctrl+C 會產生結果；未 arm／其他 PID 不接受 | 底層功能存在；UI 入口另有缺口，見 N04 |

新增證據：[counterchecks.swift／輸出](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/review2/counterchecks.log)、[journal 對照](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/review2/journal-counterchecks.log)、[lease 對照](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/review2/lease-countercheck.log)、[獨立記憶體測試](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/review2/memory-isolated.log)。完整程式位於同目錄；均使用正式編譯模組或私人 fixture，未操作真實鍵盤、Driver 或使用者 clipboard。

本輪新增驗證不灌入「既有 487 項測試」的數字。第 5 節完整 Debug／Release、Installer、Monitoring 的結果沿用同一 commit 的首輪紀錄；因 256 個 tracked files 未變更，沒有為了數量再重跑所有已通過測試。此次只補上尚待釐清的對照、獨立記憶體量測與建置觀察。

Swift Testing 的 suite `.serialized` 不會隔離其他無關測試；需要整個量測程序的獨立性，才能合理解讀 process-wide footprint。[Apple：Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization)

**證據分級：** R01／R03／R04／R05／R06 有程式呼叫鏈與隔離重現；R02 確認政策／UI 契約不一致，產品意圖尚未唯一確定；WMB-32–38 依各項維持設計／硬體待驗證狀態；下節所有優化與功能均為建議，沒有假裝已實作或量得改善。

## 9. 優化建議與可驗收標準

### O01：優先讓 CI 的記憶體量測可解讀

**優先：高。** 依 V01，將 process-wide memory 測試從主要並行群組分開，以獨立程序執行；其餘純模型及一般 fixture 維持並行。保留 +128 MiB 斷言、暖機與重複次數，失敗時保存 baseline／after、格式／尺寸、toolchain 與程序配置，不只顯示一個布林結果。

**驗收：** 單獨量測及其他測試並行群組各有獨立 gate，不能漏跑；在固定環境重複觀察結果及耗時；引入受控保留 buffer 的負面測試時仍能抓到逐次成長。此建議處理測試歸因，不表示產品有已證實的記憶體洩漏。

### O02：補上 App host 與安裝狀態轉換的整合覆蓋

**優先：高。** [Package.swift:33](/Users/steven/Documents/ChatGPT/我/Package.swift:33) 的測試依賴 Core／Platform／Support／Lifecycle，沒有直接覆蓋 App 的退出協調及功能設定接線。現有 mapper、政策各自正確，仍可能因 host 串接留下 R01／R02。抽出小型、可注入依賴的終止與功能政策協調邊界，測實際啟停／設定效果；安裝器沿用現有安全 fixture，建立 journal 發布前後及 recovery 保留／清理矩陣。

**驗收：** R01–R06 的重現先成為回歸案例，再修正式碼；持鍵退出、舊 HID 未釋放、Secure Input、失敗 rollback、外來物件及重新載入設定的斷言皆保留。測試不應僅抄寫實作中的 if 條件，也不藉由放寬 timeout／容量／安全 gate 取得通過。

### O03：改善可驗證的建置重用，先固定量測條件

**優先：中。** [prepare-hid-backend:23](/Users/steven/Documents/ChatGPT/我/scripts/prepare-hid-backend.sh:23) 每次從已驗證 archive 重建 SDK／override headers，這個設計防止使用遭修改的快取，應保留其信任檢查。可評估內容雜湊清單、只更新改變內容的檔案，以及 revision／adapter／toolchain 對應的獨立快取和互斥發布，減少重寫與跨 checkout 競爭。

本輪同版 `build-app.sh` 重跑成功，wall time **10.19 秒**、其內 Swift build **6.14 秒**；另一個直接 `swift build` 呼叫成功，但 wall time **64.24 秒**、Swift build **62.40 秒**，出現較多重建。兩者的快取／呼叫狀態尚未釐清，**不能將此差異當作 A/B 優化結果，也不能把所有重建都歸因於 SDK**。[App pipeline log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/review2/repeated-build.log)、[直接建置 log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/review2/direct-incremental-build.log)

**驗收：** 先記錄 compiler／SDK／flags／scratch key 與實際重編譯單位，再比較相同入口的冷／暖建置；內容遭修改時必須拒絕或重新驗證，不能只信 marker。僅 Docs 歷史報告變更可使用輕量 CI gate；README／UserGuide、打包資源與第一方程式變更仍依影響執行建置／測試。這項尚未實作，不承諾加速百分比。

### O04：減少輸入執行緒上未改變設定的重複工作

**優先：中，需先 profile。** [InputEngine:419](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/InputEngine.swift:419) 在 tick 後重做 processor configuration；[RemoteSourceRouter.update:33](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/RemoteSourceRouter.swift:33) 即使 routing／configuration 未變，也走過 16 個 slot 並尋找對應 producer。可以評估同一 snapshot／configuration 的快速返回或已編譯 configuration revision，避免穩定輸入期間的重複比對。

**驗收：** 用相同合成事件比較 0／1／16 個來源的 CPU、allocation、p50／p95／p99 callback 時間及輸出序列；輸出與 key-up 配對需一致。工作 gate 撤銷、來源更換、Secure Input 每事件檢查、權限 lifecycle 強制重查及按鍵釋放不得被快取遮蔽。目前沒有端到端延遲數據，不稱為已確認效能瓶頸。

### O05：在重構時優先集中所有權與錯誤狀態

**優先：中。** [BridgeController](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift) 837 行、[GuardController](/Users/steven/Documents/ChatGPT/我/Sources/InputSourceSupport/GuardController.swift) 1,153 行、[ScreenshotManager](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/ScreenshotManager.swift) 840 行，分別承擔多個 lifecycle／權限／非同步工作狀態。建議隨修復抽出可測的協調邊界與具名狀態轉換，減少多個布林旗標／全域 stage 的責任交疊；保留現有執行緒所有權與取消 token。

**驗收：** 同一安全轉換由一個協調者負責，有明確輸入、完成與失敗狀態，跨模組回歸能驗證它。這些檔案較長本身不是缺陷；不以拆檔數作為改善證據，也不在缺少回歸時大改 HID／TIS 執行緒模型。

### O06：清理維護誤導及只屬於本 App 的非復原資料

**優先：低至中。** 修正失效 HID README／legacy commands、歷史連結的可取得性，以及 [RuntimePolicy:48](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/RuntimePolicy.swift:48)「stop deadline 不會持續 gate」的舊註解，對齊目前 releaseUnconfirmed 可持續到明確 restart 的設計。診斷中的 Finder extension 欄位應說明目前不需要啟用 inert extension，避免引導無用授權。

[LaunchEmbeddedInstall:8](/Users/steven/Documents/ChatGPT/我/Resources/Installer/LaunchEmbeddedInstall.sh:8) 每次建立新的 install log，可設定有界保留策略；現有一般診斷 logger 已有兩檔／容量限制，不應誤稱它無界。回收範圍只能涵蓋本 App 確認擁有、未被待復原交易引用的資料。

**驗收：** 正式文件的現行命令可在乾淨 checkout 找到；歷史證據標示基準；log 保留政策有上限；pending recovery snapshot、retirement.unconfirmed、quarantine、共享 Driver 與使用者備份保持完整。

## 10. 建議新增／完成的功能

先核對現況：App Profile、每來源語義、HID 裝置 Windows／Native Mac 偏好、5／15／60 分鐘暫停、五分鐘診斷、輸入法守護／熱鍵／統計、原生與 Windows 截圖都已存在。以下建議補上目前可確認的缺口，沒有把既有功能重新包裝為新功能。

工作量「小／中／大」表示涉及範圍，不是工期承諾：小是局部 UI／資料整理；中是跨 UI 與狀態／持久化；大是兩種後端或新的影像處理流程與整合驗收。

### N01：一般模式也能使用的狀態說明與支援報告

**建議優先：第一批；工作量：中。** 現有 [summary](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:137) 與權限頁提供資訊，但詳細診斷被 [Advanced 開關](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/SettingsView.swift:27) 隱藏。新增一般模式可見的各功能狀態：「已啟用／實際可用／阻擋原因／建議操作」，並可明確按鈕匯出版本、SHA、權限檢查時間、backend、故障代碼及有界診斷。

**價值／驗收：** 使用者能分辨核心關閉、Secure Input、待放鍵、權限不足及 HID 未確認釋放。export 預設不包含鍵入文字、截圖、clipboard、原始序號或帳號路徑；可預覽內容。一般模式執行此操作不得因檢查狀態而自動啟動 root／Driver 或提出授權要求。

### N02：設定備份、匯入預覽與回復

**建議優先：第一批；工作量：中。** 目前有建議預設與持久化，沒有使用者可操作的完整設定 export／import。主設定位於 [SettingsStore](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:86)，輸入法偏好另在 [AppSettings](/Users/steven/Documents/ChatGPT/我/Sources/InputSourceSupport/AppSettings.swift:9) 及 [GuardSelectionStore](/Users/steven/Documents/ChatGPT/我/Sources/InputSourceCore/GuardSelectionStore.swift:6)，備份不能只保存 bridge.settings.v1。

**價值／驗收：** 換 Mac、重裝或調整規則前可回復。檔案帶 schema、來源版本及共用容量上限，先驗證再顯示差異，失敗保留舊設定；一次還原包含 App 規則、來源／裝置偏好、守護目標及熱鍵。排除 TCC grants、登入註冊、HID pin／recovery journal 等機器狀態，匯入不得隱含提權或自動安裝。先修 R04 才擴充此功能。

### N03：快捷鍵規則預覽與離線測試台

**建議優先：第一批；工作量：中。** 現有 App 規則頁只選整體 Profile，短期診斷要等真實事件。新增讓使用者選 App／Profile、輸入組合及 Windows 鍵，立即顯示預期輸出、命中規則／穿透原因；用 [KeyboardEventProcessor](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/KeyboardEventProcessor.swift:131) 等正式規則計算。

**價值／驗收：** 在啟用前看懂 Terminal Ctrl+C／Ctrl+Shift+C、Remote／VM 穿透及 Windows 鍵差異。預覽使用 UI 選取的合成值，不向作業系統或其他 App 注入按鍵，也不開全域鍵盤監聽。核心與 HID 的相同情境應有可比較結果，避免另寫一份會漂移的規則表。

### N04：完成遠端來源校準入口

**建議優先：第二批；工作量：小至中。** [calibrateRemote:731](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:731)、[RemoteCalibrationInbox](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/RemoteInputAdapters.swift:144) 及測試已存在；但目前 Sources 中 calibrateRemote／setRemoteTransport 只有宣告，calibrationNotice 也沒有 View 讀取。現有 UI 只提供來源語義 Picker，使用者無法啟動底層校準。

**價值／驗收：** 增加對指定已觀察來源的「校準」「取消」、60 秒狀態、結果確認及還原手動設定。只接受明確啟動後指定 PID／session 的一次測試組合，不能自動學習普通打字；來源退出、政策改變或取消後不得套用舊結果。此為接完既有底層功能，不是宣稱已完成支援所有遠端軟體。

### N05：可保存版本證據的實機驗收精靈

**建議優先：第二批；工作量：中。** 現有 [AcceptanceGuide](/Users/steven/Documents/ChatGPT/我/Resources/AcceptanceGuide.md) 是靜態說明。新增依一般模式／HID／UC 選取的手動驗收步驟，保存使用者確認的結果、App SHA、OS、backend、裝置類型與測試時間。

**價值／驗收：** 明確區分自動測試、使用者實測與尚未測試；升版後舊結果保留其版本，不直接沿用成新版本 PASS。先涵蓋正常退出持鍵／放鍵、Secure Input 返回、Finder rename／move、截圖取消與兩 Mac 方向。精靈不自動操作使用中的文件、刪除檔案或開啟 HID capture 來取代人的確認。

### N06：每個 App 的個別快捷鍵例外

**建議優先：後續；工作量：大。** 現有 Profile 是整個 App 的模式，快捷鍵主要是 [編譯表](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/WindowsCompatibilityRules.swift:10)，沒有每 App、每個 chord 的例外。可先做有限白名單，例如某個 IDE 保留 Ctrl+C，而其他 Ctrl+V／A／X 照常；Terminal 複製／中斷模式也可明確選擇。

**價值／驗收：** 保留目前 build 49 預設，使用者明確設定才覆寫；重複／衝突組合在儲存前可見，設定有數量／大小上限，變更時重編譯規則，不在 callback 解析 JSON。EventTap／HID、repeat、modifier 提前放開、App 切換及 Remote 穿透均須驗收。避免引入無界任意腳本執行。

### N07：選配的截圖文字擷取

**建議優先：後續；工作量：大。** 目前截圖輸出 PNG，沒有文字辨識流程。可以加一個明確的「框選後複製文字」動作，使用系統 Vision 在本機辨識；Apple 文件說明其文字辨識在使用者裝置上處理，支援依 API／語言設定取得結果。[Apple：Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

**價值／驗收：** 適合擷取畫面中的中文／英文資訊。保持現有截圖快捷鍵行為，額外動作才啟動辨識；有影像／文字大小及工作時間上限，Pause／取消／權限或政策改變後不寫入舊結果。依系統能力確認支援語言，使用合成中英文圖片測試，預設不保存畫面或文字歷史，也不新增雲端上傳流程。

建議實施順序：先修六項現存問題及 V01，再做 **N01 狀態／支援報告、N02 設定備份、N03 規則預覽**；接著 N04／N05，最後依需求評估 N06／N07。以上記錄修復前的建議與驗收條件；後續修復與實作範圍以 [修復報告](/Users/steven/Documents/ChatGPT/我/Docs/RepairReport-2026-10-15.md) 為準。
