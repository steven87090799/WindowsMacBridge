# WindowsMacBridge 審查問題修復報告

日期：2026-10-15（Asia/Taipei）。依使用者「那先修復」指示，修復 [最新 main 審查報告](/Users/steven/Documents/ChatGPT/我/Docs/CurrentMainAudit-2026-10-15.md) 的 R01–R06，並處理 V01 測試可靠性問題。

基準：已先執行 `git fetch origin --prune`，`origin/main`／HEAD 為 `949fc1f4d005b84f969d98e12e4a37249bd147f8`；修改在本機 `codex/complete-audit-repairs-20261015` 工作目錄。build 49 版本號保留，這不是新發佈版本。先前逐檔清單的 SHA 仍代表修復前 commit，沒有覆寫成修復後雜湊。

## 修復結果

| 編號 | 修改後行為 | 正式碼與回歸證據 |
|---|---|---|
| R01 · 退出還原 | 正常退出先暫停輸入輔助、停止啟用 HID 擷取，再以非阻塞等待最多約 3 秒放鍵。必須讀回確認原生 Fn／Ctrl 映射已還原，才答覆 AppKit 可以退出；未確認則提供重試／取消結束，保留復原紀錄。取消後恢復既有設定，不清除 HID 未確認釋放的保護。 | [AppMain:55](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/AppMain.swift:55)、[Controller:271](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/BridgeController.swift:271)、[Mapper:175](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/MacBookKeyboardMapper.swift:175)。[新增 5 項測試](/Users/steven/Documents/ChatGPT/我/Tests/BridgePlatformTests/MacBookKeyboardMapperTests.swift:37)：持鍵後放開、有限重試、讀回失敗、等待中斷／取消、沒有本程式映射時立即完成。 |
| R02 · 開關契約 | 設定與選單統一命名「Windows 模式總開關」，說明其包含快捷鍵、Fn／Ctrl、Finder 與截圖。關閉時子項顯示暫停並保留值，相關控制停用；登入啟動與唯音守護各自獨立。採用既有總開關語意，不變更權限、Secure Input、Session 或 HID 釋放 gate。 | [SettingsView:178](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/SettingsView.swift:178)、[選單:127](/Users/steven/Documents/ChatGPT/我/Sources/WindowsMacBridge/AppMain.swift:127)、[政策回歸](/Users/steven/Documents/ChatGPT/我/Tests/BridgeCoreTests/ReleasePolicyRegressionTests.swift:6)。使用說明及 README 同步更新。 |
| R03 · journal 發布中斷 | 成功建立 journal hardlink 後立即記錄交易狀態，記錄前保留私人 hardlink。EXIT 即使發生在 `ln` 與旗標之間，也以同一 inode 證明 journal 屬於本交易，再執行 rollback，避免留下指向已刪快照的紀錄。另一安裝者的 journal 不會被清除。 | [InstallBackend:142](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:142)、[發布:391](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:391)。[故障矩陣](/Users/steven/Documents/ChatGPT/我/Tests/InstallerTests/test_install_backend.py:373) 涵蓋發布後、旗標後、移除私人連結後、sync 後、SIGTERM、SIGKILL 後再安裝，以及外來 journal 競爭。 |
| R04 · 設定容量 | 讀取與寫入共用 65,536 bytes 上限。更新超過上限時顯示失敗，記憶體中的設定與已儲存資料均保留；下次有效更新能清除錯誤。 | [SettingsStore:87](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:87)、[寫入:123](/Users/steven/Documents/ChatGPT/我/Sources/BridgePlatform/SettingsStore.swift:123)。[新增 2 項測試](/Users/steven/Documents/ChatGPT/我/Tests/BridgePlatformTests/SettingsStoreTests.swift:12)：大量 App 規則拒絕並保留原設定；恰好 65,536 bytes 可重新載入，多 1 byte 拒絕。 |
| R05 · 復原暫存累積 | 明確記住本次新建 scratch，與舊受保護復原快照分開。復原失敗的 EXIT 會清除本次用畢 scratch；舊快照、journal、外來物件及 retirement.unconfirmed 繼續保留。 | [InstallBackend:15](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:15)、[cleanup:138](/Users/steven/Documents/ChatGPT/我/Resources/Installer/InstallBackend.sh:138)。[無效 Driver phase 連續重試](/Users/steven/Documents/ChatGPT/我/Tests/InstallerTests/test_install_backend.py:737) 及 [rollback 失敗](/Users/steven/Documents/ChatGPT/我/Tests/InstallerTests/test_install_backend.py:760) 都斷言只留下原受保護快照。 |
| R06 · 監測程序辨識 | App／Finder 的完整執行路徑後可接參數或結尾，接受官方 `--permission-relaunch`；仍保留路徑起點與邊界，排除同前綴其他程式及 root runtime。PID 上限仍為 64。 | [monitor-runtime:30](/Users/steven/Documents/ChatGPT/我/scripts/monitor-runtime.py:30)、[參數與反例測試](/Users/steven/Documents/ChatGPT/我/Tests/MonitoringTests/test_monitor_runtime.py:14)。 |

R02 的修復針對介面與既有行為不一致；截圖和 Fn 並未改成可越過總開關的獨立功能。

## V01：記憶體測試隔離

[scripts/test.sh](/Users/steven/Documents/ChatGPT/我/scripts/test.sh:16) 的完整執行分成兩個程序：一般測試先執行 435 項，再以相同組態、`--skip-build --no-parallel` 僅執行截圖記憶體測試 1 項。任一程序失敗，整個入口失敗；Debug 與 Release 都採相同方式。

原本的 128 MiB 增量斷言、暖機及 60 次處理完全保留，記憶體測試檔只更新說明註解。不是把測試排除在驗證之外，也沒有以 `.serialized` 假設能隔離其他 suite。

[新增入口測試](/Users/steven/Documents/ChatGPT/我/Tests/InstallerTests/test_test_runner.py:15) 使用私人 fake toolchain 驗證兩個程序、Release／plugin 參數傳遞、兩階段各自失敗時的 exit code、選擇性執行，以及 `--skip-build` 不重複加入。CI 步驟名稱與 README 已更新。明確指定 filter／skip、serial、清單或報告輸出時保留呼叫者的單次執行；若自行選取包含多組測試的記憶體量測，仍須選擇單獨測試或 serial。

## 驗證結果

環境：Apple Silicon、macOS 27.0（26A428）、Apple Swift 6.4。以下是本機工作目錄的驗證，不是 GitHub CI 對新 commit 的結果。

| 執行項目 | 結果 | 證據 |
|---|---|---|
| `bash scripts/test.sh --filter 'MacBookKeyboardMapperTests\|SettingsStoreTests\|ReleasePolicyRegressionTests'` | 50 項通過 | [針對性 Swift log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-targeted-swift.log) |
| `bash scripts/test.sh` | Debug 435＋1＝436 項通過；獨立記憶體測試 1.468 秒 | [完整 Debug log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-debug-full.log) |
| `bash scripts/test.sh -c release` | Release 435＋1＝436 項通過；獨立記憶體測試 1.475 秒 | [完整 Release log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-release-full.log) |
| Installer 主交易測試 | 43 項通過，411.171 秒 | [交易與復原 log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-installer.log) |
| Driver runner／SDK／root bootstrap／source version／uninstall | 14 項通過 | [其餘安裝測試 log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-installer-support.log) |
| test.sh 入口測試 | 5 項通過 | `python3 -m unittest discover -s Tests/InstallerTests -p 'test_test_runner.py' -v`；工具輸出已核對 |
| 資源監測 | 6 項通過 | `python3 -m unittest discover -s Tests/MonitoringTests -v`；工具輸出已核對 |
| `bash -n`／`git diff --check` | 通過 | 安裝腳本、測試入口與修改差異 |
| Release App 建置／離線自檢／簽章 | 通過；App 自檢、HID codec 自檢與 `codesign --verify --deep --strict` 全部成功 | [App build log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-app-build.log)、[產物驗證 log](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-app-verification.log) |

Python 合計 68 項；分三組涵蓋 InstallerTests 全部 62 項，再加 MonitoringTests 6 項。Swift 每個組態新增 8 項回歸，428 → 436。這些通過數沒有把相同測試的針對性重跑重複加進完整測試總數。

[修復驗證清單](/Users/steven/Documents/ChatGPT/我/build/current-audit-20261015/repair-verification.json) 保存 19 個修改檔案的 SHA-256、測試 log 指紋、基準／分支及產物資訊。App 產物為 `0.6.0 (49)`，來源明確標示 `949fc1f4… (modified)`，建置 UTC 為 `2026-10-15T06:39:53Z`；主程式 SHA-256 為 `a0a28683ef7e294d332d5a71c4e763c2c105d964461357d875abc2f8ff940f96`。簽章為本機 development／ad-hoc 驗證，沒有宣稱 Apple 公證或正式發佈。建置仍有原先的 CLT search-path 及 HID Sendable 診斷，這次沒有宣稱零警告。

## 既有修復與驗證界線

使用者指出的 HID 一秒期限問題已在參考分支修復，且包含於本次基準。這次沒有改動 `Tools/HIDBackend` 的正式碼；正式 pointing flush 沒有加回舊 heartbeat 年齡條件。既有 ConnectionLease、held safety、未確認釋放 gate、Secure Input、Finder 焦點及截圖 bounded read 回歸均包含在完整測試。

安裝測試只執行私人副本和替代目的地／命令；未更動 `/Applications`、系統服務、Driver、實際鍵盤映射或 TCC。R01 的還原邊界有 fixture 覆蓋，AppKit 退出接線通過編譯與原始碼核對；真實持鍵退出／取消視窗、硬體 HID 交接、跨 Mac／UC 與授權變更仍需實機驗收。

本輪完成問題修復與 V01。原審查的其他效能／維護建議及 N01–N07 新功能仍保留為建議，未混入此修復。未安裝、發佈或推送遠端。
