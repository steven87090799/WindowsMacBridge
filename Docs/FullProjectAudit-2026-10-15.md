# WindowsMacBridge 全專案程式審查報告

> **歷史報告，現行結論已由 [最新 main build 49 審查](/Users/steven/Documents/ChatGPT/我/Docs/CurrentMainAudit-2026-10-15.md) 取代。** 本檔基準為舊 build 46；未先同步造成 F01（HID 一秒期限）與 F03（輸入法 pending）被誤套到最新版本。兩項在最新 main 均已修復，不能將下方「8 項尚未修復」當作 build 49 的狀態。其餘六項經新版重新驗證，詳見新報告。

審查日期：2026-10-15，Asia/Taipei。審查對象為目前工作目錄的 **0.6.0 build 46**，分支 `codex/input-source-guard-intent`，commit `2e1b21ffc557e3c5c0e4bc10b84342c765495041`。開始審查時工作區乾淨；本次只新增報告、覆蓋清單及本機驗證證據，沒有修正正式碼、變更測試或安裝 App。

**確認 8 項缺陷：P1 一項、P2 五項、P3 兩項。** 現有自動測試通過，但沒有覆蓋這些跨模組或中斷時序。建議先處理 HID 複合裝置轉送、正常退出還原及安裝復原，再評估發行；目前不能以測試通過宣稱硬體、跨機或 Driver 已驗收。

## 1. 範圍與覆蓋方式

版本控制內共有 **238 檔**：234 個文字檔、25,382 行，以及 4 個二進位圖示。行數使用 `splitlines()`，包含檔尾未換行的最後一行；因此與直接對二進位檔也執行 `wc -l` 的數字不同。

- 194 個檔案、19,309 行完成逐檔逐行閱讀，涵蓋全部第一方程式、測試、建置／安裝腳本、CI、設定及兩份後端說明。
- 1 個 3,654 行 JSON fixture 完整解析及展開檢視，核對全部 78 個 manipulator 的條件、輸入、輸出及去重關係。
- 29 個文件／指南做現行行為與歷史版本的一致性核對；10 份第三方授權文字做存在性與打包清單檢查；4 個圖示核對格式及尺寸。這些不冒稱逐行程式安全審查。
- 跨檔追查 production 呼叫鏈、狀態所有權、取消／重試、權限、來源識別及安裝回復，並以隔離 fixture 重現可執行的問題。

**逐檔路徑、行數、審查方式及 SHA-256** 見 [完整覆蓋清單](/Users/steven/Documents/ChatGPT/我/Docs/FullProjectAudit-2026-10-15-files.json)。清單以審查前的 238 個 tracked files 為基準，不把本報告或驗證輸出灌入覆蓋數字。

| 分區 | 檔案 | 行數 | 審查重點 |
|---|---:|---:|---|
| BridgeCore、InputSourceCore、BridgeWorkGate、HIDProtocol 及對應測試／fixture | 67 | 8,944 | 規則、modifier／press 配對、來源撤銷、政策、圖片預算、輸入法狀態機 |
| BridgePlatform、對應測試、FinderSync | 54 | 6,248 | EventTap、XPC、AX 動作、截圖／PDF、原生映射、持久化、資源載入 |
| HID backend、工具、安裝器、scripts、CI、Python 測試 | 50 | 3,722 | 實體裝置所有權、C++ 輸出、交易／復原、打包、監控 |
| 主 App、InputSourceSupport、對應測試、Package 與 App plist | 24 | 4,049 | 啟停、SwiftUI、功能設定、TIS／Carbon、權限／登入協調 |
| 其餘文件、授權文字 | 39 | 2,419 | 現行說明、歷史證據、打包與連結一致性 |
| 二進位圖示 | 4 | 不適用 | PNG／ICNS 格式、1024／32 pixel 尺寸 |

未納入逐行第一方審查：`.git` 內部資料、ignored 建置產物／舊日誌、下載的第三方 SDK、由 SDK 產生的 override headers。SDK 固定 revision 與 SHA-256 的建置驗證有檢查，但這不等於完成第三方實作或授權法律稽核。已安裝版本與目前執行中的 App 不屬於這份原始碼基準。

## 2. 缺陷總表

P1 代表高影響、應先修復的功能故障；P2 代表需排程修復的正確性問題；P3 代表較低頻率或診斷／維護問題。本輪沒有確認 P0 缺陷，也不據此推論不存在其他缺陷。

| ID | 優先度 | 問題 | 主要位置 | 證據 |
|---|---|---|---|---|
| F01 | P1 | HID 一秒後丟棄複合裝置的指標報告，仍持續接管裝置 | [DeviceCapture.swift:401](/Users/steven/Documents/ChatGPT/我/Tools/HIDBackend/Sources/HIDRuntime/DeviceCapture.swift:401) | production 呼叫鏈、期限條件核對 |
| F02 | P2 | 按鍵仍按住時正常退出，Fn／Ctrl 交換留在系統 | [MacBookKeyboardMapper.swift:167](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/MacBookKeyboardMapper.swift:167) | 實際編譯模組＋假鍵盤 fixture |
| F03 | P2 | TIS 請求後進入 Secure Input，驗證退出卻留下未完成交易 | [GuardController.swift:843](/Users/steven/Documents/ChatGPT/我/Sources/InputSourceSupport/GuardController.swift:843) | 未修改正式碼＋記憶體 provider 重現 |
| F04 | P2 | Windows 核心開關同時停用仍開啟的截圖與 Fn 功能 | [RuntimePolicy.swift:45](/Users/steven/Documents/ChatGPT/我/Sources/BridgeCore/RuntimePolicy.swift:45) | 實際 Core 模組政策重現、UI／host 呼叫鏈 |
| F05 | P2 | 安裝 journal 已發布、旗標尚未更新時中斷，刪除復原快照 | [InstallBackend.sh:298](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:298) | 私人安裝 fixture 的 SIGTERM／命令失敗注入 |
| F06 | P2 | 可儲存超過 64 KiB 的設定，重開卻拒絕載入 | [SettingsStore.swift:120](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:120) | 實際編譯模組＋隔離 UserDefaults suite |
| F07 | P3 | 失敗復原每重試一次，遺留一份完整 payload | [InstallBackend.sh:153](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:153) | 私人 fixture 連續兩次失敗，副本 1→2→3 |
| F08 | P3 | 權限重新啟動參數使監控誤報 App 停止 | [monitor-runtime.py:31](/Users/steven/Documents/ChatGPT/我/scripts/monitor-runtime.py:31) | 正式 regex 與正式啟動參數比對 |

### F01　HID 接管與 pointing 輸出使用不同租約條件

**觸發條件：** 選用 HID，成功接管 descriptor 支援的 keyboard＋pointing 複合服務；設定與前景保持不變超過一秒。一般 EventTap 模式不走這條路徑。

`DeviceCapture.configure()` 第 90 行才更新 `lastHeartbeat`，但 GUI 的 [HIDBackendClient.update():132](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/HIDBackendClient.swift:132) 只在設定變動時送出 configure，已沒有定期心跳。capture lifecycle 在 `DeviceCapture.swift:307` 改用連線 lease，因此仍能保持 seized；`flushPointing()` 第 401–403 行卻仍要求 `systemUptime - lastHeartbeat < 1`，不符合就直接 return。

**影響：** 滑鼠位移、滾輪及按鈕事件停止轉送，實體服務仍被獨占。若 button-down 在一秒內送出、button-up 在一秒後到達，release 也可能遺失而留下虛擬按鈕按住狀態。鍵盤輸出不受同一舊期限約束，所以這不是完整失效後正常交回原生裝置。

**證據界線：** 已確認 production 路徑及 age 0.9 秒通過、1.0／1.1／100 秒拒絕的條件；沒有實際 seize 複合裝置。硬體後果是依已確認路徑推導，並非本輪實機紀錄。

**修正與驗收：** pointing 與 keyboard 共用同一份已驗證 lease／安全狀態；不能轉送時共同釋放所有權及按鈕。補 HIDRuntime adapter 測試，涵蓋不變設定下超過一秒，以及期限兩側的 down／up，再用可丟棄環境完成實體複合鍵盤／滑鼠驗收。

### F02　正常退出沒有等待 Fn／Ctrl 還原完成

**觸發條件：** 啟用本機 MacBook Fn／Ctrl 原生交換，退出時任意按鍵仍未達 neutral，例如透過鍵盤執行退出並持續按住修飾鍵。

`MacBookKeyboardMapper.stop()` 第 167–170 行先停止觀察再執行一次 `refresh()`；`restore()` 第 180–182 行在非 neutral 時保留映射與 journal，等待稍後重試。但 [AppMain.swift:54](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/AppMain.swift:54) 的 terminate handler 直接執行 stop，[BridgeController.swift:275](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:275) 也先移除 mapper callback，再停 mapper／engine，沒有延後終止或保留還原機會。

**重現：** 假內建鍵盤先套用交換；改為 `keysNeutral=false` 再呼叫正式 mapper.stop。輸出仍為 `swapped=true`、`restorePending=true`、`awaitingNeutral=true`，觀察已關閉，journal 仍存在；之後放開鍵但沒有 refresh，交換不會自行復原。[重現輸出](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/platform-repro.log)

**影響：** 正常退出後原生交換可能繼續存在，與指南「正常退出後還原」不符。Apple 說明指出映射隨 keyboard service 存續，系統重開或服務移除才會清除，因此不能假定 App 退出會自動撤銷。[Apple TN2450](https://developer.apple.com/library/archive/technotes/tn2450/_index.html)

**修正與驗收：** 以 termination coordination 在 neutral 且還原完成前延後退出，提供有界等待及明確處理；保留 journal 的失敗復原用途。新增 stop／quit 持鍵測試，並在 MacBook 上驗證正常退出及放鍵順序。強制終止的既有限制與本問題分開處理。

### F03　驗證期間的 Secure Input 轉換遺留 pending selection

**觸發條件：** TIS selection 回 `noErr`，尚未收到確認通知、來源仍未切換；在 400 ms 驗證之前進入 Secure Input，令安全檢查或 live selection gate 失敗。

`scheduleVerification()` 第 843–846 行直接 return，沒有清除 `pendingInternalSourceID` 或建立 Secure Input recovery。第 871–877 行雖有 Secure Input 分支，卻已被前方 `!isSecureInputEnabled` guard 擋住，無法處理這個時序。

**重現：** 直接編譯未修改的 GuardController／InputSourceManager，以假 provider 回 noErr、保持來源不變；設定 Secure Input，700 ms 後解除，再等 3.5 秒。選取次數仍為 1、`selectionInProgress=true`，沒有自動重試。[重現輸出](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/guard-repro.log)

**影響：** 在新的 App、來源或按鍵等外部事件發生前，交易可能停滯。父層 [BridgeController.swift:338](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:338) 又依 `selectionInProgress` 壓低 layoutSupported，可能連帶暫停快捷鍵。後續事件或 policy 更新可能解除，所以不稱為不可恢復。

**修正與驗收：** 安全狀態打斷驗證時明確收尾或轉為有界復原狀態，不能直接遺留交易。新增「noErr→驗證前 Secure Input→解除且沒有額外通知」測試，驗證 pending 清除／恢復、來源結果及 host shortcut gate。

### F04　獨立功能開關依賴核心快捷鍵旗標

[SettingsView.swift:178](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/SettingsView.swift:178) 將「Windows 核心快捷鍵」、「MacBook 鍵盤模式」及「Windows 快捷截圖」分成獨立開關。`BridgeController.swift:516` 卻以核心開關決定 shortcutEnabled，而 RuntimePolicy 第 45–55 行的實體正規化、截圖都再依賴它。

**重現：** 在權限及 session 正常、`shortcutEnabled=false`、`screenshotEnabled=true` 下，實際 Core 回傳 `permitsScreenshots=false`、`permitsPhysicalNormalization=false`。[重現輸出](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/policy-repro.log)

**影響：** 關閉核心快捷鍵會停止截圖並還原 Fn 交換，另外兩個開關仍顯示開啟；使用者無法只選用這兩項功能。

**修正與驗收：** 分開共用 session／pause／權限／Secure Input 條件與各 feature flag。若產品確定採總開關，應同步更改 UI 名稱、說明與相依控制。新增 core off＋screenshot on／Fn on 的 host 整合情境，保持原安全條件。

### F05　Journal 發布窗口的退出清理會刪除其快照

`InstallBackend.sh:298` 已用 hardlink 發布 `.install-recovery`；第 299–301 行還要刪暫存 journal 並 sync，第 302 行才設定 `bridge_switched=1`。在這個窗口中斷或命令失敗時，EXIT cleanup 第 98–106 行不移除已發布的 journal，卻刪除 stage。

**重現：** 以既有私人安裝 fixture 與系統命令 stubs，在 ln 成功後注入 SIGTERM：退出碼 -15，journal 存在、其指向的 snapshot 已不存在。令發布後的 rm 失敗也得到同樣殘留。未執行真正管理員安裝。

**影響：** 下次 recovery 第 134–138 行拒絕缺失的 snapshot，[UninstallBackend.sh:8](/Users/steven/Documents/ChatGPT/我/Resources/Installer/UninstallBackend.sh:8) 也因 pending journal 拒絕操作。App 可能顯示安裝復原中並阻擋進階輸入，正常重試無法解決。這個窗口發生在切換 App／Driver 前，不據此聲稱當下已破壞舊 App。

**修正與驗收：** 明確追蹤「本程序已發布 journal」與 stage 保護責任，讓所有 publication 後的退出都保留可用快照或安全移除自己發布的 journal；不能只把需要回收的事實綁在較晚的 switched 旗標。補 ln 後、rm 後、sync 前後的中斷及命令失敗測試。不要以直接刪掉使用者真實 recovery journal 作為修正。

### F06　設定儲存與讀取大小限制不一致

`SettingsStore.update()` 第 120–123 行僅驗證 next.valid，編碼後直接保存；valid 第 36–40 行沒有 overrides 的數量或長度上限。初始化第 95 行卻拒絕超過 65,536 bytes 的資料。

**重現：** 隔離 suite 中加入 2,000 個 overrides，正式模組寫出 135,452 bytes，`valid=true`、儲存沒有錯誤；重新建構 SettingsStore 後 `enabled=false`、overrides=0 且回報無法讀取。[重現輸出](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/platform-repro.log)

**影響：** App 可以自行寫出下一次無法讀取的設定；大量自訂規則後重開會停用功能。原始 blob 在讀取失敗時仍保留，並非當場刪除；若使用者接著儲存安全預設，才可能覆寫原資料。

**修正與驗收：** 寫入前檢查 encoded bytes，與讀取共用限制；必要時限制／清楚回報 overrides 邊界。失敗時保留前一份可用設定。測 65,536 邊界、超限拒絕、重開 round-trip 及錯誤後原資料保留。

### F07　失敗復原遺留當次新建的 payload

每次執行在 `InstallBackend.sh:13` 建立新 stage、第 176 行複製完整 payload。進入 recovery 第 153–154 行後，將全域 stage 換成舊快照，當次新 stage 只放在區域變數。若 driver.phase 檢查或 rollback 失敗，EXIT 第 87–89 行直接保留退出，新 stage 無人回收。

**重現：** 使用既有 interrupted-install fixture，保留舊 snapshot 並令 driver.phase 無效；連續重試兩次，含 payload 的 stage 數量由 1→2→3。這是私人目錄重現，沒有刪除真實 recovery 資料。

**影響：** 每次失敗重試多留一份 App、Driver packages 等 payload，可能持續累積 root 私有暫存磁碟用量。

**修正與驗收：** 分別追蹤當次 scratch 與受保護 recovery snapshot；只保留復原必需的舊快照，回收當次未使用 scratch。失敗及成功復原測試都核對目錄數量與舊 snapshot 完整性。

### F08　監控未接受主程式的正式啟動參數

`monitor-runtime.py:31` 對主 App 使用 executable path 加結尾 `$`；[RelaunchApp.sh:8](/Users/steven/Documents/ChatGPT/我/Resources/Installer/RelaunchApp.sh:8) 正式透過 `--permission-relaunch` 開啟 App，程序 command 含參數而不匹配。Finder 分支已允許空白／結尾，主程式分支沒有。

**重現：** 相同 executable path，無參數 regex 匹配 true，附上 ` --permission-relaunch` 為 false。

**影響：** 正常重新啟動的 App 被記錄為 down，CPU／RSS／footprint 資料缺失；會妨礙後續資源判讀，不能據此認定 App 崩潰。

**修正與驗收：** 允許合法 path 後的參數邊界；測無參數、正式 relaunch 參數及避免匹配相似 executable 名稱。

## 3. 已執行驗證

環境：Apple Silicon arm64、macOS 27.0／26A428、Apple Swift 6.4，deployment target macOS 14。以下為本輪實際執行，沒有沿用歷史報告或遠端 CI 結果。

| 檢查 | 結果 | 證據 |
|---|---|---|
| 完整 Swift Debug | PASS 354：VirtualHID 20、InputSourceSupport 13、InputSourceCore 40、BridgePlatform 132、BridgeCore 149 | [Debug log](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/swift-debug.log) |
| 完整 Swift Release | 同一套 354 項全部 PASS | [Release log](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/swift-release.log) |
| Installer／rollback／SDK／source version | PASS 38 | [Installer log](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/installer.log) |
| Monitoring | PASS 5 | [Monitoring log](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/monitoring.log) |
| Release App 建置、Finder extension、strict codesign、registry self-check | PASS，build 46、28 個 registry entries；來源 clean 且 revision 符合基準 | [Build log](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/build.log) |
| App deep／strict codesign、自身 self-check、HID codec self-check | PASS；離線 codec 不連 Driver | [驗證結果](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/verification-checks.json) |
| Shell／plist／JSON／Python 靜態檢查 | 18 shell、6 plist、4 JSON、9 Python PASS | [靜態檢查](/Users/steven/Documents/ChatGPT/我/build/audit-20261015/static.json) |
| 隔離故障重現 | F02／F03／F04／F06 已執行正式模組或未修改正式碼；F05／F07 使用私人安裝 fixture；F01／F08 核對正式條件 | 同目錄重現原碼及輸出 |

共 **397 項不同的現有測試**通過（354＋38＋5）；Debug／Release 重跑不重複加總。新缺陷的隔離重現另計，沒有修改既有測試來取得通過結果。

編譯警告保留於 log：CLT 不存在的可選 framework／library search paths、SDK 內 Asio 的 size_t→socklen_t 轉型、RemoteInputAdapters 的 deprecated cString initializer，以及測試中的 weak var 提示。本輪沒有證據將這些警告列成新的可重現 runtime 缺陷。

本輪完成 App 建置與簽章檢查；沒有建立新 ZIP／DMG、執行無 `.git` archive 的完整建置、ASan、Hosted CI、安裝／啟動 GUI、授予權限、連接 Driver、擷取實體裝置或向其他 App 注入事件。這些未執行項目不算 PASS。

## 4. 各模組結論與保留的正確設計

| 區域 | 本輪結論 |
|---|---|
| 核心規則／modifier／press ledger | 逐行檢查及現有高頻／多來源模型通過；未確認額外必報缺陷。不能由此證明兩把實體鍵盤的 OS aggregate flags 順序。 |
| Remote／UC | 保留 PID／程序身份、來源 session／work gate、already-translated 與 unknown passthrough；沒有將未驗收 transport 標為 Verified。 |
| EventTap／動作派送 | 有配對清理、bounded inbox、generation／前景／來源檢查；AX、程序、圖片等慢工作在 callback 外。真實投遞與 TCC 時序仍需測試。 |
| 截圖／圖片／PDF | 保留 single-flight、取消 token、encoded／decoded／pixel budgets、PDF resource／inline image preflight。限制是輸入及本程式 buffer 預算，不能當整體 RAM 硬上限。 |
| HID／VirtualHID | 純編碼及 lifecycle tests 通過；F01 是舊期限與新 lease 的整合遺漏。實際 seize、pointer releases、輸出停滯需 adapter 及硬體驗收。 |
| Fn 原生映射／journal | 保存所有權、驗證寫回、避免覆蓋外部映射的設計保留；F02 顯示正常退出交接未完成。 |
| 輸入法 | 明確目標、有限重試、pause、host policy 及主 queue 邊界存在；F03 是 verification 的中途安全狀態缺口。 |
| 安裝／更新／移除 | 固定套件 hash、簽章、root-owned runtime pin、共享 Driver 保留、交易快照均保留；F05／F07 需修正 publication／失敗清理。fixture 通過不代表 DriverKit replacement 已驗收。 |
| 設定／UI／監控 | F04、F06、F08；其餘未確認新的必報問題。Swift 5 mode 的 TIS／HID adapter 還依賴既定執行緒約束，不能把 Swift 6 host 編譯通過當成所有 data race 已證明不存在。 |

下列項目經交叉檢查後**不列缺陷**：FinderSync 的空 `directoryURLs` 與停用 publisher 是既定移除監看設計；不建議重新監看根目錄。`sameCapturePolicy` 不比較逐裝置偏好是保留其他鍵盤 hold 的設計，DeviceCapture 另有逐裝置交回路徑。Remote 的 tombstone 用來阻止舊 repeat 復活，沒有足夠 transport 證據把它本身判成卡鍵缺陷。

## 5. 文件及測試可達性問題

1. [HID backend README](/Users/steven/Documents/ChatGPT/我/Tools/HIDBackend/README.md:6) 仍要求不存在的 `build-hid-helper.sh`、`package-hid-release.sh`，指向舊 `Sources/BridgeHIDHelper`，root 入口仍寫 `--serve`；目前為單一 App 與 `--hid-service`。應改成現行 build/package 與離線自查方式。這是開發文件錯誤，與 F01–F08 分開計數。
2. 文件掃描找到 10 處失效的本地 Markdown 引用，全部在舊 PreReleaseRepair 報告：部分是未隨 Git 保存的歷史 build 證據，部分為已移除的舊程式／腳本。保留歷史數字可以，但應明確標示其來源快照及是否仍可取得，避免當成目前路徑。
3. `NativeScreenshotObserver` 與其直接接收原生存檔的測試仍存在，production 目前沒有建構／接線該 observer。現行截圖主要由快捷鍵 gate→本 App capture lifecycle 執行；observer 測試通過不能當作現行 ⌘⇧3／4 完整成功證據。
4. `VirtualHIDTests` 依賴 VirtualHID／HIDLifecycle，沒有直接測 HIDRuntime 的 DeviceCapture。因此目前大量 codec／模型測試無法抓出 F01。需增加可注入 clock／transport 的 adapter 層測試。
5. 現行測試缺少持鍵 stop／正常退出、驗證中途 Secure Input、各獨立開關組合、設定儲存／讀取同一容量邊界、journal publication 窗口，以及 recovery 失敗的 scratch 數量驗證。

## 6. 待實機驗收與未定事項

以下是證據缺口，不另算確認缺陷，也不會以擅自操作使用中的鍵盤或系統設定補驗收：

| 情境 | 需要記錄的結果 |
|---|---|
| HID 複合服務 | 超過一秒的持續指標輸入、button-down／up、USB／Bluetooth 斷線、Driver 不 ready／輸出停滯後釋放 |
| Fn／Ctrl | MacBook 內建交換、外接不受影響、正常退出持鍵／放鍵、crash 後 journal 恢復、睡眠與登入 |
| 原生／Windows 截圖 | ⌘⇧3／4、Win+Shift+S／PrintScreen 及視窗擷取、Control Center 代收事件、取消／pause／權限變更、多螢幕 |
| TCC／Secure Input | 同一 App 內進入／解除安全輸入、驗證中途變動、實際授權撤銷及更新後重啟 |
| HID idle 權限撤銷 | status freshness 現在依目前連線狀態；沒有從原始碼確認 OS 撤權時必定觸發哪個通知／失效回呼，需量測釋放及 UI 更新，不推測為已確認 bug |
| Universal Control／Remote | 兩台 Mac 雙向、來源 Terminal→目的 TextEdit、兩端 App 同開、混合鍵盤、hidden producer PID、各 client 轉送設定 |
| Finder／視窗／IME | 真實 AX 焦點、剪下跨目錄、永久刪除確認、未儲存窗口、唯音組字／候選／Carbon hotkey |
| 進階安裝復原 | 真實管理員取消、Driver activation／reboot、共享版本、強制中斷／斷電及系統延伸功能狀態 |
| 資源 | 同版本／同 PID 的長期 idle＋輸入／切換負載；App、screencapture、WindowServer、系統 clipboard 的總峰值與延遲 |

測試 fixture 未觀察到的 SDK 共享快取並行重建、打包並行執行及特殊 PDF／ICC native codec 額外配置，保留為後續壓力測試範圍，不以可能性充當缺陷。

## 7. 修復順序與完成標準

1. **先修 F01**：統一 HID lease，加入含 button release 的 adapter 回歸，再完成實體複合裝置驗收。
2. **修 F02、F05**：正常退出要完成還原；journal 每個發布中斷點都要保持可恢復。不得為通過測試跳過 neutral 或刪除舊快照。
3. **修 F03、F04、F06**：完整收尾 selection transaction，釐清獨立功能 gate，令設定成功儲存必能重新載入。
4. **修 F07、F08 及文件**：回收當次 scratch、補正式啟動參數監控，更新已失效的開發入口。
5. 針對每項先保留重現，再執行對應回歸及完整 Debug／Release。只有實際執行的硬體／跨機／Driver 情境才能補上驗收通過。

本次交付為審查與證據，**8 項缺陷尚未修復**。本機詳細 log／harness 位於 [audit-20261015](/Users/steven/Documents/ChatGPT/我/build/audit-20261015)，該目錄為 ignored；可提交的報告與逐檔 manifest 位於 Docs。此結論僅適用於上方精確 commit 與檔案雜湊，不能套用至其他分支、較新版 release 或已安裝 App。
