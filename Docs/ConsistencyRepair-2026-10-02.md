# WindowsMacBridge 0.5.16 (build 28) 修復與驗證報告

查核日期：2026-10-01 至 2026-10-02。基準 commit：07101539e4663d7cb435e9cf7b152d44cc790d1e，分支 codex/unified-windows-input-layer。App/helper IPC 同步升至 protocol 5；Driver ABI 仍為 1.8.0 / protocol 7。

## 2026-10-02 最新補修（後續段落的 316 項為上一輪紀錄）

本輪先 regression 再修改 production：修正 A→B→A coalesced App 切換丟失 held Ctrl；Driver 首次半套安裝納入 durable journal，加入已核對 7.3.0→8.6.0 的 package/files/receipt/activation 回復、forced-kill recovery、atomic phase、corrupt phase 保留 snapshot、running App/foreign clients/orphan registration 阻擋。相容共用 daemon 不重啟；Driver 回復失敗不啟動服務；pending recovery 阻擋 uninstall。

新增 one-shot DriverProcessRunner：90 s timeout、process group cancellation、64 KiB log 上限、拒絕 log hardlink/symlink，原生程序測試驗證取消子程序及 log bound。已實際以 arm64-apple-macos14.0 編譯，otool 確認 minos 14.0；沒有增加 runtime timer。

PDF 原本只檢查 page geometry，可放行夾帶 40000×40000 raster 的 8×8 頁面，已在 production image worker 補 resource/form/mask/inline image preflight。遍歷上限 256 nodes／12 levels／64 entries，內嵌 decoded bytes aggregate 不超過既有 budget；驗證四通道以內常見 device/ICC/indexed colorspace，未知格式保守拒絕。CoreGraphics 實際 scanner 在 EI 提供 inline stream，已用獨立 fixture trace 確認，再補 oversized inline regression；正常 raster/ICC/inline PDF、TIFF/JPEG/PNG 相容測試通過。scanner/operator/content stream 使用 defer 釋放。

**最新全套 333 項通過**：Root Release 283（Core 139、Platform 110、InputSource 34），helper 15，Installer Python/native 30，Monitoring 5；bash syntax / git diff --check 通過。logs：`build/consistency-verification/root-release-final.log`、`helper-final.log`、`installer-complete.log`、`monitoring-final.log`。上一輪 ASan 316 項不能當作最新 PDF／installer 的 ASan 證據；本輪新來源尚未重新封裝或安裝，沒有使用者輸入／Clipboard／真實 Driver 測試。

7.3.0 和 8.6.0 的 dext 都是 1.8.0，daemon client protocol 才是 6→7；不宣稱任意 DriverKit ABI 升級或 OS activation 完整驗收。新 rollback pkg 已核對官方 checksum／Developer ID Installer／notarization、實際 dext/manager 版本及 strict signature；system-extension 核准／重開機／共享第三方仍需實機驗收。

本機 GUI 查核仍為 0.5.15 (27)：AX=true、posting=false。**P0 實機驗收阻擋及未知 HID/hidden Remote PID/其他 Driver ABI 等 P1 缺口仍存在，不能宣稱正式上線或所有組合一致。** 接手位置與不確定部分另見 [複雜部分交接](ComplexityHandoff-2026-10-02.md)。本輪修改另外包括 `Resources/Installer/DriverTransaction.sh`、`DriverProcessRunner.c`、`UninstallBackend.sh`、`Sources/BridgePlatform/PDFImageBudget.swift`、`Tests/InstallerTests/test_driver_runner.py`、`test_uninstall_recovery.py`、`Tests/BridgePlatformTests/ScreenshotTests.swift`，以及既有清單內的 runtime/router/App-transition/installer/package/tests 文件。所有修改仍未 commit。

**仍是待實機驗收的候選版，不能宣稱已可正式上線，也不能宣稱所有電腦／Remote／UC 組合完全一致。** 下列狀態將程式修復、自動測試、實機驗收分開。原本 0.5.15 的報告保留為歷史紀錄。

最新安裝前檢查：上一輪 0.5.16 (28) App 建置、self-check 及 strict codesign 已確認成功；本機仍是 0.5.15 (27)，標準安裝路徑沒有 HID helper，官方 Driver pkg receipt 不存在。缺少 receipt 不等於已排除所有手動安裝方式。本輪另找到並修正「Ctrl 保持按住切換 App 後的新 Ctrl+C 不翻譯」，最新原始碼完整測試合計 316 項通過。**現有 Release App 是本輪 modifier 修正前的包，不能當成最新修正的安裝包。** 尚未重新封裝、安裝或修改 TCC／Driver。

## 1. 本機「事件輸出」問題

實際 GUI 查核：macOS 27.0 (26A428) 上，已安裝 App 為 0.5.15 (27)，GUI 顯示 Accessibility 已取得、Event posting 未取得；按原本的事件輸出設定按鈕開啟「裝置控制和資料取用」，WindowsMacBridge 的系統開關已開。沒有改動系統權限。Terminal/Codex 啟動的同一個 App CLI 顯示 granted，這不能替代 Finder 啟動 GUI process 的 TCC 身分／授權結果。

- API 沒有廢除：本機 SDK 27 仍有 CGPreflightPostEventAccess / CGRequestPostEventAccess，Apple 文件也仍列出這些 API。UI 是同一個授權頁；App 的 Accessibility 與 PostEvent 能力仍需分別讀回驗證。[Apple Request API](https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess())、[Apple Preflight API](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess())。
- 已確認的程式根因：舊程式只開啟 PrivacyAccessibility 頁，requestAccessibility 只呼叫 AXIsProcessTrustedWithOptions；整個舊 production path 沒有呼叫 CGRequestPostEventAccess。Runtime 必須同時有 AX / posting，否則安全釋放 synthetic keys 及翻譯無法成立，所以 Ctrl+C 被停用。
- 修正：KeyboardPermissionRequest 只在明確按鈕操作時呼叫缺少的原生 request API；忽略 request 回傳值，重新讀取兩個 preflight 結果。權限頁合併成一個「要求／修復授權」，partial grant 顯示缺少按鍵控制。沒有把 false 改成 true，沒有刪除 PostEvent 安全檢查。
- 權限分工：鍵盤控制使用同一系統頁；HID helper 為另一個 executable，Input Monitoring 仍獨立。Screenshot 開啟時顯示 Screen Recording；Finder extension / login 在選用項目，App listening 放診斷資訊。
- 可能的另一個因素：已安裝 App 是 ad-hoc 簽章，designated requirement 綁 cdhash；本機 `security find-identity -v -p codesigning` 顯示 0 valid identities。重編會改變身分，舊系統項目可能不再對應目前版本。這是合理推論，沒有用它冒充已確認的唯一 OS 根因。沒有偽造弱化 designated requirement 或自動重設 TCC。
- **實機結果未完成**：候選版尚未替換已安裝 App/helper。必須由同一 GUI identity 執行新版要求流程並重新驗證；若系統舊項目已開啟仍不通過，移除舊項目後加入 /Applications 的目前版本。OS 的使用者核准不能由離線測試完成。

## 2. 各問題根因、實際修正與範圍

| 問題 | 根因 | Production 修正 | 尚有限制 |
|---|---|---|---|
| UC source Finder / AX 操作錯誤 Mac | HID action 只帶來源前景 PID，這不是目的端 authority | Helper 的 actionsEnabled=false；Host 不接受 helper performAction 取得目的端權限；移除 Host 不再使用的 action dispatcher。Denied action 保留原始 down/up，不吞掉按鍵 | 接收端 WindowServer routing 必須兩台 Mac 實測 |
| Source Terminal、目的文字 App 的 Ctrl+C 不同 | source App context 決定所有 Ctrl 語意；receiver 只穿透 | 全 Windows / all-keyboard HID 模式保留 App-sensitive raw Ctrl，接收端 annotated recipient==本機 foreground 才套 App 規則。普通 App/layout 切換不清除 raw physical holds | 兩端都需新版；混合 Native Mac 缺 source-device 證據；source 保護 Remote/VM/Game 的情境仍需驗收 |
| Raw Win+Tab 被 macOS 原生 Cmd+Tab 先吃掉 | WindowServer 系統快捷鍵先於 annotated delivery | 純 HID Win+L/R/Tab 依開關先編碼，隨輸入傳送；不做 source AX 或 Clipboard。接收端 Cmd+Tab 等只允許窄範圍 native session routing、private event source、自有 marker、即時 policy/source gate | 接收端原生 switcher / UC forwarding 的時序未實測；Win+R/Tab 原預設關閉仍保留 |
| Modifier/Alt release 與 App 變更 | synthetic Command 的側別與 physical Alt 不能混成全域 flags | 固定 NativeAppSwitchLatch 保留左右 Command 側別；原始 modifier edge / owned up 可清理帳本。recipient 缺失只允許既有 native session 的 Tab continuation；不啟動新 App-sensitive down | 這是 native macOS Cmd+Tab 鍵位映射，沒有新增自製 MRU、視窗列舉或切換 UI |
| Ctrl 保持按住切換接收 App 後複製失效 | 所有 runtime generation 都 invalidate；Controller 在純 App 切換也先停用 Engine；configure 強制 awaitingNeutral | Runtime snapshot 新增 modifierEpoch 記錄真正的安全／ownership 中斷。只有完整 policy 與設定相同的 App 切換保留實體側別；舊輸出照常 drain、舊 repeat/up 留 tombstone，舊 actions/screenshot work 照常取消。實體與同一 Remote producer 使用相同 continuity 決策 | Pause／Secure Input／session／backend／device／layout／設定／權限變更維持 neutral；跨越未知或 Remote/VM/Game ownership 不允許保留 |
| 未擷取外接鍵盤失去 Windows 行為 | HID 模式拒絕全部 physical-looking EventTap；未知 composite 不安全 seize | 全 Windows 模式在已確認接收 App 的最後語意階段處理 raw HID / UC 與未擷取標準鍵盤事件。Helper 不先翻譯同一組 App-sensitive chord；不做盲目 HID+EventTap 各改一次 | public CGEvent 沒有 device ID；Native Mac 混合配置仍保守停用部分增強 |
| Composite keyboard+mouse | 原 descriptor 僅接受 Boolean keyboard / consumer；抓取 service 會遺失 pointer axes / buttons | Discovery 編譯 role map，最多 2048 elements；標準 relative X/Y/wheel/pan 和 32 buttons 全部轉送。16 device button ledger；同 timestamp 合併、motion 在 button edge 前送、disconnect 釋放自己的貢獻；<=1023 拆成最多 9 個 8-byte reports | absolute pointer、touch、未知／未完整轉送 descriptor 不 seize；ANSI/ISO/JIS/BT 與特殊 vendor field 尚待實測 |
| Fn mapping backend 衝突 | raw transport ignore source layout 後仍啟用 native UserKeyMapping，可能與 HID 交換兩次 | usesNativePhysicalMapping 與 helper hand-back 共用 HIDCapturePolicy；Remote/VM/Game/Disabled 交回 native ownership；source Terminal raw capture 不啟用第二個 native swap | UserKeyMapping 真正 crash / reboot restore 待實機 |
| 手動穿透 Fn 仍交換 | inputModifier 無視 manualPassThrough；normalization policy 沒排除 manual | raw / legacy HID 均在 manual pass 保留實體 Fn / Ctrl；native mapping policy 同時停用 normalization | 保留 neutral handoff 與 restoration journal，沒有跳過 restore pending |
| Brightness Up → Enter | consumer key 沒有目的端 App/focus authority | Host 禁止 source helper 此轉換，UI 明示暫停支援、可清除舊設定；Brightness 保持原 consumer 功能 | optional Finder brightness Enter 暫不提供；不是偷偷仍套來源 Finder 規則 |
| Driver 任意不同 pkg version 就拒絕 | pkg version 被誤當作 SDK/driver ABI | 驗證官方 8.0.0–8.6.0 都是 driver 1.8.0 / protocol 7；驗證 root-owned/writable/symlink、Apple anchor / Team / signing ID、receipt 與 daemon/dext binary version，符合就沿用，不重裝共用 Driver | v7.3 protocol 6 / 未知 ABI 拒絕；任意 shared Driver ABI upgrade / activation rollback 尚未完成 |
| codesign requirement 參數 | bare expression 被 codesign 當作 filename | inline requirement 加 `=`；加入真正 csreq parser test，stub 也不再放過錯誤格式；原廠 daemon/dext 實際 strict requirement verify 通過 | 真正 installed Driver / systemextension activation 未執行 |

Driver 版本證據來自官方 exact tags 的 version.json，而不是只看「版本較新」：[官方 Driver repo](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)、[v8.5 version.json](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/v8.5.0/version.json)。Pinned 8.6 pkg 的 postinstall 會 kill 共用 daemon，因此沒有用 blind upgrade 破壞其他使用者。僅 App/helper rollback 不等於 DriverKit activation rollback。

參考 Karabiner：實際讀取本機 reference clone d130433e5854eeff125f6ed45f6ac1bdad0aeeab；採 IOHID per-device / bounded virtual output 與 pointer 同 timestamp 合併的做法。[DEVELOPMENT](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md) 說明 CGEvent fallback 缺 device metadata、virtual HID 會遺失 PID/user data；它沒有提供跨機目的 App 的神奇 API。本文不以「參考 Karabiner」當作 UC / Remote 已通過的證據。

既有必修項目保留並重新跑完整 suite：per-device physical/shortcut ownership 的 Ctrl+C→Tab、重疊 Ctrl+C/Right、各種釋放順序、兩裝置；Finder cut state 跨資料夾與 focus 分類；AX Alt+F4 保留 unsaved prompt；screenshot cancel/timeout/failure classification/epoch；single runtime transition；bounded log / AX / source work；首次 driver receipt 正常、query error 失敗；update staging / pin / journal / rollback；無 .git build fallback。本次沒有只修改測試使舊錯誤通過。

## 3. 新增與擴充 regression tests

上一輪新增 29 項 distinct tests，本輪安裝前檢查再新增 7 項；相對基準 280 項，合計 316 項。Debug / Release / ASan 是同一套的不同執行模式，沒有重複灌大項目數。

- Core 14 項：DestinationSemanticsTests 7、HIDDescriptorTests 4、DestinationAppSwitchTests 2、HIDTranslationTests manual Fn 1。涵蓋 source Finder 不執行 action、source Terminal raw hold 不因 App/layout 改變遺失、receiving TextEdit vs Terminal、recipient 缺失/不同 PID、global Win chords、legacy denied action 不吞原始 pair、composite full-field coverage / unknown reject / buttons disconnect，以及 Command 側別與原始 Command 重疊。
- Platform 9 項：KeyboardPermissionRequestTests 3（missing-only、partial grant、request return 不當 grant）、DestinationRuntimeTests 4（raw profile gate、helper epoch 不當 target authority、capture epoch、native Fn ownership）、NativeSessionEmitterTests 2（offline CGEvent/private state、自有 marker、matching flagsChanged cleanup）。沒有 post 真正鍵盤事件。
- Helper 2 項：pointing 全位移 / 32 buttons 編碼；bounds / capacity / invalid value 不寫出界與清空報告。沿用 100,000-report codec stress。
- Python installer 4 項：8.0–8.5 reuse、receipt 和 binary version 不一致拒絕、compatible Driver 在 App/helper fail 後不改動、native requirement parser。
- 本輪 Core 4 項、Platform 3 項：持續 Ctrl 跨 App 後新複製；舊 C repeat/up 不復活、重疊 Right Arrow 不繼承 Command、左右 Ctrl 不混淆；invalidated／不一致 modifier／設定／受保護 ownership 不跳過 neutral；Remote 同一 producer 保留但舊 work token 失效、producer session 改變不保留；完整 lifecycle／permission／device／backend policy gate；快速合併多個 App 切換仍保留 Ctrl，但中間的 Pause／Secure Input／Remote ownership 中斷不能消失。
- 擴充原本 Remote lease/switcher tests、RuntimePolicy manual pass tests、IPC source-action authority tests。舊版 helper protocol 4 被新版 5 拒絕，不接受不認識的新設定。

每項新增 API/production behavior 都先留 red evidence，再修改 production。證據目錄 build/consistency-verification 包含 descriptor-red、pointing-red、destination-red、destination-runtime-red、permission-red、app-switch-red、native-session-red、delivery-red、hid-global-red、fn-ownership-red、source-actions-red、manual-fn-red、driver-compatibility-red、driver-signature-red 等。早期兩個 fixture 問題（Ctrl edge 初始化與 dext Info.plist 位置）及 Swift Testing mutating macro 限制已修正；不把 fixture 修正冒充 production 修復。

本輪 red evidence：install-readiness.log（切換 App 後新 Ctrl+C 實際 passThrough）、app-coalescing-red.log（快速 App 切換合併會失去 Ctrl）。修正 KeyboardEventProcessor、RuntimePolicy、InputEngine、RemoteSourceRouter 及 Controller；沒有只放寬測試期望。

## 4. 完整測試與 build 結果

環境：Apple Silicon、macOS 27.0、Swift 6.4 / Command Line Tools；Swift Testing macro plugin 由 scripts/test.sh 發現，不修改 SDK。

| 驗證 | 結果 | 證據 |
|---|---|---|
| 完整 Root Debug | 上一輪 PASS，272；本輪使用完整 ASan suite 驗證最新原始碼 | root-debug-final.log |
| 完整 Root Release | 上一輪 PASS，272；本輪未重跑此模式 | root-release-final.log |
| 完整 Root ASan（最新原始碼） | PASS，34 InputSource + 107 Platform + 138 Core = 279，沒有 ASan error | root-install-readiness-asan.log |
| Helper Debug / Release | 上一輪 PASS，各 15 | helper-debug-final.log / helper-release-final.log |
| Helper ASan（最新原始碼） | PASS，15，沒有 ASan error | helper-install-readiness-asan.log |
| 全部 Python Installer / SDK / source version（本輪重跑） | PASS，17 | installer-install-readiness.log |
| 全部 Monitoring（本輪重跑） | PASS，5 | monitoring-install-readiness.log |
| 官方 daemon / dext strict requirement | PASS，真正官方 bytes，無安裝 | driver-daemon-signature.log / driver-extension-signature.log |
| 上一輪 Git checkout Release App/helper build / self-check / codesign | PASS；App build 38.11 s，App/helper strict signature 與 self-check 通過；不含本輪 modifier 修正 | build-app-final.log / helper-debug-final.log |
| 真正無 .git ZIP App/helper build | 待最後確認 | archive-app-build.log / archive-helper-build.log |
| Bundle allowlist / DMG / HID package payload checksums | 待最後確認 | package-dmg.log / package-hid.log |
| diff whitespace / shell syntax / Python syntax | PASS | static-final.log |
| 新 head Hosted CI | 尚未執行；不當成本地通過 | 不沿用前一版本 Hosted checks |

ASan 不能證明所有 retain cycle / live TCC / DriverKit ownership；XPC fixture 的 weak-controller 釋放檢查與 bounded collection tests 另有執行。

## 5. 大圖實測與效能檢查

使用新增 BridgeImageBenchmark 獨立程序呼叫真正 ScreenshotImagePreparation，fixtures 由逐列生成器產生，不讀使用者圖片、不啟動 event tap/Driver/Clipboard/截圖。BridgeImageBenchmark 沒有打入 App allowlist。

| 輸入 | 最大 RSS | peak physical footprint | 行為 |
|---|---:|---:|---|
| baseline 程序 | 6.86 MiB | 1.83 MiB | 無圖片處理 |
| 6000×6000 RGBA PNG | 11.80 MiB | 3.45 MiB | 直接沿用 PNG，沒有建立 bitmap，0.013 s |
| 6000×6000 Deflate TIFF | 289.03 MiB | 280.45 MiB | decode → PNG，0.457 s |
| 6000×6000 PDF | 288.20 MiB | 280.53 MiB | render → PNG，0.443 s |
| 6001×6000 PNG | 11.58 MiB | 3.28 MiB | decodeFailure，預先拒絕過 pixel budget |

RSS 與 footprint 是不同指標；這是 isolated codec process cold run 的 peak，不是整個 App / screencapture / WindowServer / 接收 App 的總峰值。36 MP 解碼約 144 MB，TIFF/PDF native codec 仍可能有第二份內部 bitmap，因此 144 MiB per-decoded-image guard 不代表 whole-process peak 144 MiB。沒有聲稱本次已驗收系統 Clipboard 的大圖峰值。

保持 dimension / pixel / decoded bytes / encoded buffer budgets；PNG 輸出不先產生額外 TIFF representation。保留 failure 分類及單一 screenshot job；沒有為省 RAM 取消 epoch/session/Secure Input。可以再研究 ImageIO transcode 或 bounded strips，但必須先驗證色彩、透明度、格式與 native codec 的峰值；不能用品質降級或移除 budgets 假裝最佳化完成。

本次效能修正：discovery 預編譯 cookie role、16-device ledger 固定容量、pointer 合併只排一個 weak runloop drain、移除不使用的 HID Host action dispatcher；native system emitter 不排 detached job。沒有新增高頻 timer。原 EventTap 250 ms safety、helper/host 250 ms heartbeat / lease、host 1 s observation 保留；HID 模式停用 InputEngine 250 ms polling；停用功能時停止相應 timer。30 s HID discovery reconciliation 仍是既有補救，不是逐鍵列舉裝置。

## 6. 最後模組衝突 review

- Source AX / Finder / Clipboard：helper configure actionsEnabled=false；Host performAction 同步拒絕、不排 Task；接收 action 必須 recipient/context 驗證再進 fixed 16-slot dispatcher，執行前後仍檢查 work token / generation / foreground / Secure Input。
- HID / EventTap：raw App-sensitive transport 不在 source先翻譯；receiving physical stage 只有 full Windows scope 啟用。Remote producer 各自16-slot ledger；self marker / own PID 排除。未知 PID=0 state=0 保留；public event 缺device/peer證據的混合配置不假裝支援。
- Pause/backend/session/secure/disconnect：沿用 transition / neutral / tombstones / safe release；Fn native restore pending 必須完成才新 seize。Manual pass 額外還原 Fn 語意。Pointing motion/button contribution 一起釋放。
- App-only continuity：modifierEpoch 保留合併前的中斷紀錄；完整 immutable policy／EngineConfiguration 比較含 device preferences 與 producer ownership。只省略沒有安全中斷的 modifier invalidate，照常 drain 輸出及取消背景工作；不清除已有 awaitingNeutral，不修補成假 grant、不新增 polling／queue／AX 查詢。
- Callback：快速 map/state/decision/native input delivery；没有同步 AX traversal、file I/O、shell、image processing 或 UI。diagnostics ring 128/5分鐘、producer inbox 16、HID devices16、presses256、output outstanding256/500ms fault；pointer最多9份報告。
- Swift weak runloop block / timers、XPC weak receiver 沒有增加新 cycle；discovery service arrays 在 disconnect 移除，fixed ledgers reset。ASan 與 offline lifecycle 不代表所有 live resources 已驗收。
- Finder 未知/文字 focus 不執行 trash；brightness consumer 暫停 Enter，沒有把 source Finder 當 receiver。未知 focus 保守保留。
- Installer stages App/helper/pin/license before switch，錯誤恢復 owned services / App，recovery journal 保留；相容共享 Driver不重裝。不相容 Driver upgrade / activation rollback 並未完成。
- Release FinderSync 使用 -O；保留 -Osize 選項與明確 resource/extension allowlist。沒有刪除 SDK/vendor license notices；benchmark / test fixtures / source headers不作runtime资源。

## 7. 仍需實機驗收與 P0/P1

**P0 上線阻擋仍存在：端到端 UC recipient authority / WindowServer ordering 及目前 GUI TCC 授權尚未完成驗收。** Source helper 誤操作本機 App 的程式路徑已封閉並有回歸，但不能用它宣稱 UC 目的端行為已 Verified。任何 key/consumer/remote routing 缺 authoritative evidence 都保守保留，而不是猜 target。

**已知 P1 功能缺口**：unknown/absolute/touch HID coverage；Native Mac 混合來源識別；hidden producer PID / multi-peer / 不同 Remote client 實際傳送策略；optional brightness Enter 暫停；任意 shared Driver ABI upgrade / full DriverKit activation rollback。不同電腦的原生 OS/client 行為不能由幾個 CGEvent metadata 值自動證明一致。

必須實機完成：

1. 六核心路徑：Windows外接→Mac、Mac外接→UC→MacBook、MacBook內建本機、MacBook內建→UC→Mac、Windows Remote→Mac、Mac Remote→Mac；兩端Bridge、兩裝置同時及往返。
2. UC source Finder → receiver text、source Terminal → receiver TextEdit，确认 source 不改 Clipboard / Finder / window；held Ctrl/Shift/Alt跨機及 native Win/CmdTab；快速 focus / recipient=0 fallback。
3. 真正 GUI grant/revoke/upgrade/ad-hoc 身分、helper InputMonitoring / Driver activation / SecureInput / login/sleep，CLI granted 不作 GUI 證明。
4. 實體 composite pointer report ordering、button releases、BT斷連、consumer/Fn/TouchID、多鍵盤同側 modifier、seize與native restore；direct HID VM/Game/Remote client不能被接管。
5. 真正 shared 8.x舊版本共用、daemon 已被其他軟體使用、installer fail / forced kill / reboot、DriverKit system extension状态與回復；不能卸別的軟體 Driver。
6. 完整 screenshot + WindowServer + system Clipboard 大圖峰值，TCC cancel/permission failure/disk/codec failure，舊job pause/backend/session/feature停用後不寫Clipboard。

沒有任何 Remote transport 或 UC 路徑被列為 Verified。詳見 Resources/AcceptanceGuide.md；本機候選包及原始碼可供验收，但目前不能承诺「任何组合完全一样」或正式上線。

2026-10-02 使用者追加指示：先檢查是否全部好了，再考慮安裝。本次讀取已完成的 build 結果，確認上一輪 App build 成功；再找到、補 regression 並修正 Ctrl 跨 App 問題，完整最新 suite 316 項通過。因上述 P0 驗收阻擋與 P1 功能缺口尚未全數完成，本次沒有重新建置安裝包或執行本機安裝；也沒有重複等待建置。

## 8. 修改檔案清單

- `Docs/ConsistencyRepair-2026-10-02.md`
- `Docs/UnifiedInput-2026-10-01.md`
- `Package.swift`
- `README.md`
- `Resources/AcceptanceGuide.md`
- `Resources/Info.plist`
- `Resources/Installer/HIDHelper-Info.plist`
- `Resources/Installer/InstallBackend.sh`
- `Resources/Installer/READ-ME-FIRST.md`
- `Resources/UserGuide.md`
- `Sources/BridgeCore/BackendCapabilities.swift`
- `Sources/BridgeCore/DestinationSemanticPolicy.swift`
- `Sources/BridgeCore/HIDDescriptorPolicy.swift`
- `Sources/BridgeCore/HIDTranslationEngine.swift`
- `Sources/BridgeCore/KeyboardEventProcessor.swift`
- `Sources/BridgeCore/NativeAppSwitchLatch.swift`
- `Sources/BridgeCore/PermissionChecklist.swift`
- `Sources/BridgeCore/RemoteSourceRouter.swift`
- `Sources/BridgeCore/RuntimePolicy.swift`
- `Sources/BridgePlatform/HIDBackendClient.swift`
- `Sources/BridgePlatform/InputEngine.swift`
- `Sources/BridgePlatform/KeyboardPermissionRequest.swift`
- `Sources/BridgePlatform/NativeSessionEmitter.swift`
- `Sources/BridgePlatform/ScreenshotManager.swift`
- `Sources/HIDProtocol/HIDProtocol.swift`
- `Sources/WindowsMacBridge/BridgeController.swift`
- `Sources/WindowsMacBridge/SettingsView.swift`
- `Tests/BridgeCoreTests/DestinationAppSwitchTests.swift`
- `Tests/BridgeCoreTests/DestinationSemanticsTests.swift`
- `Tests/BridgeCoreTests/HIDDescriptorTests.swift`
- `Tests/BridgeCoreTests/HIDTranslationTests.swift`
- `Tests/BridgeCoreTests/InstallReadinessRegressionTests.swift`
- `Tests/BridgeCoreTests/ReleasePolicyRegressionTests.swift`
- `Tests/BridgeCoreTests/RemoteSemanticRegressionTests.swift`
- `Tests/BridgePlatformTests/BackendOwnershipTests.swift`
- `Tests/BridgePlatformTests/AppTransitionSafetyTests.swift`
- `Tests/BridgePlatformTests/DestinationRuntimeTests.swift`
- `Tests/BridgePlatformTests/HIDProtocolTests.swift`
- `Tests/BridgePlatformTests/KeyboardPermissionRequestTests.swift`
- `Tests/BridgePlatformTests/NativeSessionEmitterTests.swift`
- `Tests/InstallerTests/test_install_backend.py`
- `Tools/HIDBackend/Sources/BridgeHIDHelper/DeviceCapture.swift`
- `Tools/HIDBackend/Sources/VirtualHID/VirtualHID.cpp`
- `Tools/HIDBackend/Sources/VirtualHID/include/VirtualHID.h`
- `Tools/HIDBackend/Tests/VirtualHIDTests/ReportTests.swift`
- `Tools/ImageBenchmark/Benchmark.swift`
- `scripts/generate-image-budget-fixtures.py`
