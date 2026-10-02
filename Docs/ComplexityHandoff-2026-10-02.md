# WindowsMacBridge 複雜部分與接手位置

日期：2026-10-02。Repository：`https://github.com/steven87090799/WindowsMacBridge.git`。
後續 reviewer 複查：`Docs/ReviewerAudit-2026-10-02.md`。該輪又修改了來源，依使用者要求不執行任何測試、建置或封裝；本文件下方的歷史通過數字不適用於 reviewer 最新修正。
目前分支 `codex/unified-windows-input-layer`，基準 commit `07101539e4663d7cb435e9cf7b152d44cc790d1e`。
**本輪及前輪修正仍在工作目錄，尚未 commit。接手時務必取得修改檔及新增檔；只 clone GitHub 不會取得這些修正。**

## 1. 跨電腦來源、目的端語意與事件 ownership

使用者要求每台電腦／任意組合都像 Windows。困難在 UC 與各 Remote client 沒有共同的公開來源 metadata 契約：裝置 ID、producer PID、source session、目的端 App 不一定齊全；來源端或 Remote client 也可能先攔截 OS 快捷鍵。禁止僅用 foreground App 猜來源，亦禁止 HID/EventTap 重複翻譯。

已完成：HID 傳送原始 App-sensitive 按鍵，來源 helper 不執行 Finder／AX／Clipboard action，接收端檢查 recipient；Remote 使用逐 producer ledger、manual override 與 already-translated 語意。

仍不確定：真實 UC 的 WindowServer recipient/order、hidden PID、未知 virtual/composite HID、多 peer、各 Remote client 的傳送方式及雙端同時安裝。沒有任何 transport 列為 Verified。unknown/absolute/touch HID 尚未完整覆盖。

入口：`Sources/BridgePlatform/InputEngine.swift`、`Sources/BridgeCore/DestinationSemanticPolicy.swift`、`Sources/BridgeCore/RemoteSourceRouter.swift`、`Sources/BridgePlatform/RemoteInputAdapters.swift`、`Tools/HIDBackend/Sources/BridgeHIDHelper/DeviceCapture.swift`。驗收路徑在 `Resources/AcceptanceGuide.md`。

## 2. 多裝置持鍵與非同步生命週期

Ctrl/Shift/Alt 會跨快捷鍵、App、裝置重疊，舊 synthetic modifier 不能汙染新快捷鍵。安全中斷必須 release 並等待適當 neutral；普通 App 切換則不能丟掉實體 Ctrl。所有 detached action／Screenshot 工作仍須驗證 session、generation、backend、pause、Secure Input。

已完成：per-device/active-press ledger、bounded ledgers、release tombstone、immutable policy；modifierEpoch 保留被 mailbox coalescing 隱藏的安全中斷。新增 Ctrl 持住換 App、新 Ctrl+C，以及 A→B→A 快速往返的實際 processor/router regression。

仍不確定：真實 HID→EventTap 交接、virtual report 與 physical neutral 的事件順序、UC 持 Ctrl/Shift/Alt 跨機、多鍵盤同時斷連，以及 TCC/Secure Input 在實際 callback 之間改變。不能移除 neutral、lease、session validation 換取測試通過。

入口：`Sources/BridgeCore/RuntimePolicy.swift`、`KeyboardEventProcessor.swift`、`HIDTranslationEngine.swift`、`Sources/BridgePlatform/InputEngine.swift`、`HIDBackendClient.swift`。
測試：`Tests/BridgeCoreTests/InstallReadinessRegressionTests.swift`、`Tests/BridgePlatformTests/AppTransitionSafetyTests.swift` 及原 HID/ownership/release suites。

## 3. macOS 權限、共用 Driver 與安裝回復

AX 與 CG event posting 共用系統頁面，但檢查不是同一個 API；不能把 AX=true 當作 posting=true。ad-hoc 更新也可能改變 TCC 身分。目前本機舊 App 0.5.15 (27) GUI 仍顯示 AX=true、posting=false；新申請流程尚未安裝驗證。

已完成：使用真正 CGRequestPostEventAccess、重新讀取授權、統一鍵盤控制 UI。安裝先 staging/verify/journal 再 switch；首次 Driver 半套失敗、7.3.0→8.6.0、forced kill、receipt/files/activation rollback 有私有 fixture regression；相容 8.x 不重裝、不重啟共用 daemon。復原失敗保留 root snapshot 且不啟動服務；解除安裝不得破壞 pending recovery。Driver manager job 有 timeout/process-group cancellation/64 KiB log 限制。

版本限制：7.3.0 與 8.6.0 的 Driver 都是 1.8.0，daemon protocol 分別 6／7。這個升級不能宣稱為任意 DriverKit ABI 升級。只支援已簽章/checksum/版本核對的套件，未知版本及仍有共用 client 的舊版升級拒絕修改。

仍不確定：真實 OS 核准／重開機／DriverKit replacement 與 downgrade、第三方 co-owner、登入使用者改變時的啟動情境。Fixture 不等於真實管理員安裝通過。

入口：`Sources/BridgePlatform/KeyboardPermissionRequest.swift`、`Resources/Installer/InstallBackend.sh`、`DriverTransaction.sh`、`DriverProcessRunner.c`。
測試：`Tests/InstallerTests/test_install_backend.py`、`test_driver_runner.py`、`test_uninstall_recovery.py`。

## 4. 截圖格式与記憶體邊界

Screenshot auto-copy 支援系統產生的 PNG/JPEG/TIFF/PDF；PDF 頁面尺寸不等於內嵌圖片解析度。可把 40000×40000 raster 縮到 8×8 頁面：舊檢查會放行，CoreGraphics 隨後可能嘗試解碼大圖。

已重現並修正：繪製前檢查 resource/XObject/form/mask/inline image 的 dimensions、pixel/decoded-byte aggregate budget，限制 dictionary/array 遍歷及 recursion；正常 raster/inline PDF 仍需相容測試。PNG 輸出有 encoded budget，scanner/content/operator table 必須釋放，不能增加常駐 bitmap。

仍不確定：原生 codec/ICC/複雜 PDF parser 的額外配置，以及完整 App＋screencapture＋WindowServer＋系統 Clipboard 的總峰值。此前 isolated TIFF/PDF 36 MP 測得約 280 MiB footprint；不能把 144 MiB per-image budget 當成 whole-process 上限。未驗證的 color space 保守拒絕，不假裝所有 PDF 都支援。

入口：`Sources/BridgePlatform/ScreenshotManager.swift`、`PDFImageBudget.swift`、`ScreenshotCaptureDriver.swift`。
測試：`Tests/BridgePlatformTests/ScreenshotTests.swift`、`ScreenshotRuntimeTests.swift`、`NativeScreenshotJobTests.swift`。Offline benchmark：`Tools/ImageBenchmark`。

## 接手要求

先保留工作目錄，再閱讀上述入口及 `Docs/ConsistencyRepair-2026-10-02.md`。不要重新引入自製 Alt+Tab/MRU switcher，不要假 grant、弱化簽章、關閉 Secure Input、取消 session/epoch 或用高頻 timer 猜來源。

完整測試指令：`./scripts/test.sh -c release`、helper Swift tests（依 `scripts/build-hid-helper.sh` 的 macro plugin/scratch 設定）、`python3 -m unittest discover -s Tests/InstallerTests`、`python3 -m unittest discover -s Tests/MonitoringTests`。

最新 log 在本機 `build/consistency-verification/`（ignored，不會隨 Git clone 取得）。舊報告的 316 項是上輪紀錄；不能套用至最新 PDF／installer 修改。最新測試結果另外記錄，不把 pending 工作當通過。尚未把本輪來源封裝／安裝到本機，也不能宣稱所有 P0/P1 完成或已可正式上線。

本輪結束檢查：最新完整套件 333 項通過（Root Release 283、helper 15、Installer 30、Monitoring 5）。PDF oversized XObject/form/inline 與正常 ICC/raster/inline 相容 regression 通過；DriverProcessRunner arm64 macOS14 target 實際編譯通過，bash syntax/diff check 通過。這些是離線及 fixture 證據，未執行真實 GUI 授權、Driver 安裝或新 App 封裝。當前不再卡在 PDF 編譯／已重現的 oversized raster 放行問題。
