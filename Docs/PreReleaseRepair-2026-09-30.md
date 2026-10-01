# WindowsMacBridge 上線前修復與驗證報告

審查基準：0.5.13（build 25），2026-09-30。修復候選版：0.5.14（build 26）。最終本機驗證日期：2026-10-01，Asia/Taipei。

**判定：尚不可宣稱可正式上線。** 已修正本次可重現的鍵盤狀態、Finder、截圖、首次安裝及狀態交接問題，新增 regression tests 並重新執行原有完整測試。仍有實體輸入、Universal Control、Remote、TCC、Driver 安裝／升級的驗收缺口，以及下文列出的 P1 限制。自製 Alt+Tab 已確認沒有 runtime 實作，本次沒有重新加入。

本報告記錄本機驗證完成時的結果；當時變更尚在工作目錄。後續 commit、PR 與 Hosted CI 狀態以對應 GitHub PR 為準。沒有建立 release、安裝 Driver、更新使用中的 App，或操作真實使用者的 Clipboard。測試中的 Clipboard 為私人 pasteboard；安裝器測試將正式腳本複製到私人 fixture，將管理員命令與目的地替換成 stub。`--self-check` 不建立 EventTap、不接管裝置、不連接／啟動 Driver。

## 1. 範圍與修改檔案

已閱讀第一方 Core、Platform、App、InputSource、HID helper、Finder extension、建置／安裝／封裝腳本與原有測試，並依跨模組呼叫關係檢查狀態交接。第三方 SDK 使用固定 checksum；不將 SDK／vendor headers 的授權聲明視為完成逐行安全或授權稽核。

完整修改檔案清單由工作目錄產生，列於本報告末尾。重點入口：

| 模組 | 主要修改 |
| --- | --- |
| BridgeCore | HID 按鍵／來源 ownership、press ledger、runtime policy、Finder cut/focus policy、截圖生命週期與快捷鍵、圖片預算、有界 log／mailbox |
| BridgePlatform | EventTap release、HID XPC ownership 交接、AX 動作 worker、截圖 process／圖片處理、Fn/UserKeyMapping journal |
| App／InputSource | 單一 runtime transition、所有功能 pause/session/generation、遠端角色設定、事件合併、timer 生命週期 |
| HID helper／C++ | 支援的鍵盤接管範圍、裝置狀態失效、停止交接 ACK、報告 modifier rollover |
| Finder extension | 路徑選單上限、停用時取消 directory observation、Release optimization |
| Installer／build／CI | 首次 receipt 查詢、staging／驗證／rollback／中止復原、ZIP version fallback、明確 bundle allowlist、SDK checksum、防止 Python optimize 跳過驗證 |

## 2. P0 根本原因與實際修正

| 問題 | 根本原因 | Production 修正與目前結果 |
| --- | --- | --- |
| Ctrl+C 後 Ctrl+Tab 失去 Ctrl | 使用持續累積的 consumed modifier 狀態，C 放開後沒有從 active press 重新推導；實體 modifier 與 synthetic modifier 混用 | 每個來源裝置追蹤實體 modifier；每個 shortcut press 記錄 consumed contributor／輸出 modifier。C key-up 後重算，只恢復仍實體按住的 Ctrl。Ctrl down → C down/up → Tab down/up → Ctrl up 已通過。 |
| 快捷鍵重疊造成 Command／Option 汙染 | 不相容 shortcut 的輸出 modifier 被合併；舊字母可在新 modifier 下繼續出現在 HID report | 新 chord 退休不相容舊 press；C 尚未放開時按 Right Arrow，不合併 Command／Option，也不讓舊 C 復活。C++ 報告依序釋放舊鍵、清除舊 modifier，再送新 chord。 |
| 不同裝置／釋放順序 | 單一狀態不足以表達 modifier 的來源；disconnect 後 slot bit 可殘留於其他 press | 固定 16 device slots／256 press slots；owner bitset 綁定真正提供 modifier 的裝置。disconnect 清除所有 press 的該 slot ownership，新裝置不能繼承舊 modifier。左右 Ctrl、順序反轉、快速 repeat、多裝置皆有測試。 |
| Brightness Up → Enter | consumer usage 的轉換未受 Finder 與獨立功能旗標約束 | `finderBrightnessEnterEnabled` 預設 false；必須本機 Finder、Finder 功能開啟及獨立選項開啟才轉 Enter。其他 App 保持 consumer key。 |
| 首次 Driver 安裝 exit 1 | `set -euo pipefail` 下以 `pkgutil --pkg-info` 查詢不存在的 receipt，正常「未安裝」被當致命錯誤 | 先查 `pkgutil --pkgs`，無 receipt 走首次安裝；真正查詢錯誤、異常 version／不同共用 Driver 版本仍失敗。fresh／already installed／查詢失敗測試通過。 |
| Finder Ctrl+X 導航後遺失 | 所有後續 Finder action 一律清除待移動狀態 | 只有 Copy、新的 Cut、刪除等操作取消；開資料夾、上一層、路徑導覽、rename/new folder 不取消。Ctrl+V 依同一 Clipboard changeCount、PID、5 分鐘期限移動。epoch 改變會清除，不能跨 pause/session/backend 重用舊 Cut。 |
| Finder Delete 誤刪文字 | 只依 Finder 前景或 AX role 推論檔案選取，未區分 filename editing／sidebar／unknown | 有界 AX focus reader 先識別文字；確認 selection 的 file URL metadata 並走到 AXWindow 才判定 files。只有 files 送 Command+Backspace；text／unknown 送原生 forward delete，無刪檔 modifier。永久刪除仍需另開啟與確認。 |
| Alt+F4 語意錯誤 | 直接 Command+W 或「最後視窗」Command+Q 無法代表所有 App 的關窗行為 | 移除 `altF4QuitLastWindow` runtime/config/IPC 設定；只對目前 App 的 focused window、enabled close button 執行 AXPress。按下前再確認 PID／focused window／epoch／Secure Input；無可用 close button 時回報，沒有 W／Q fallback。未儲存提示交由 App 處理。 |
| 截圖舊工作仍改 Clipboard | native process／decode 完成後只看 enabled，無完整 host token 與取消；off/on 可讓舊工作復活 | runtime generation＋capture epoch/revision＋job token；pause、停用、backend、foreground、session、Secure Input、設定變化取消舊工作。完成及 Clipboard commit 前再次驗證 live 授權／session／PID／policy。單一 slot 保留到實際完成，120 秒 timeout，SIGTERM 後 2 秒只對仍持有的 child 升級終止。 |
| 截圖失敗一律取消 | 非零 process exit、無輸出、permission／disk／codec 失敗混為 cancel | 區分 userCancelled、permissionDenied、processFailure、diskFailure、decodeFailure、encodeFailure、timedOut、policyCancelled；bounded stderr 判讀 native cancel／permission／disk 訊息。無互動截圖 exit 0 但沒有圖片為 processFailure，不能當使用者取消。實際 macOS screencapture 各版本結果仍需實機驗收。 |
| backend/UI/runtime 不一致 | 手動切換、建議設定、啟動、權限、pause 使用不同更新順序，舊 backend 尚持有裝置時新 backend 已啟動 | `BridgeController.publish()` 統一 immutable policy transition。先停舊 EventTap／動作，再處理 native mapping、Finder、Screenshot、HID、新 EventTap、InputSource。HID stop ACK 前 gate 新 backend；1.5 秒 timeout 保持關閉，不能假裝已釋放 ownership。 |

這些是 production code 修正；沒有僅放寬測試讓舊行為通過。原有 HID 測試中兩項期待改成正確 contract：C-up 時實體 Ctrl 還按住就保留 Ctrl；Brightness 的特殊轉換需明確 opt-in。其他原有測試仍完整執行。

## 3. P1 與效能修正

| 項目 | 根因與修正 | 限制／驗收 |
| --- | --- | --- |
| device → backend ownership | 不再僅接管 Apple 834；`allKeyboards` 接管可安全辨識的 USB／Bluetooth 簡單 keyboard descriptor，最多 16 裝置。HID／EventTap／native exclusive ownership；HID 模式沒有第二套盲目的 EventTap／screenshot tap。 | 複合 mouse/multitouch、無法安全接管的 descriptor 維持 native，不保證 Windows 行為。EventTap 公開 API 沒有可靠 device ID，尚不能宣稱所有未接管裝置也可安全混合翻譯。 |
| Remote／兩端 Bridge／UC | 前景 Remote App 不能代表輸入來源。新增 automatic、windowsReceiver、macReceiver、alreadyTranslated、sourcePassThrough；角色變化失效所有舊工作並等 neutral。來源端可穿透、接收端決定是否翻譯。 | 手動角色是有效控制，沒有 transport provenance 的來源不能自動推斷。不同來源鍵盤 Win modifier、Client 轉送、雙端 Bridge 與 UC 跨機仍需實測。 |
| Windows screenshot shortcuts | 共用快捷鍵描述支援 Win+Shift+S、Alt+PrintScreen、Win+PrintScreen、PrintScreen，支援框選／傳統全螢幕偏好與 PNG 自動複製，兩個 backend 均有路徑。 | HID 依 USB usage 區分 PrintScreen 0x46 與真正 F13 0x68，修正 Carbon 105 alias 誤捕捉。EventTap 僅看到 macOS keycode 105，不能可靠還原鍵帽／來源語意。 |
| 圖片峰值 | 原先 eager bitmap／TIFF 可同時建立多份大影像。先驗 file bytes、dimension、pixel count、depth／decoded bytes；PNG 沿用 mapped immutable encoded data，其他格式只保留一個 CGImage。PNG encoder 使用 CGDataConsumer，超限 chunk 在 append 前拒絕。 | 上限：檔案／編碼 64 MiB、每邊 16,384、36,000,000 pixels、decoded estimate 144 MiB。僅輸出 PNG，不 eager 建立 alternate TIFF。ImageIO／PDF 內部配置與實際 RSS 尚未量測，這些是輸入與本程式 buffer 預算，不能當成整個 process 的硬 RSS 上限。 |
| callback 與慢工作 | AX traversal、Process 啟動、WindowServer metadata、圖片／disk 工作在 callback 外。動作 inbox 16 筆；一個 drain／串行動作 worker；截圖 single-flight。callback 只查表、bounded ledger、try-lock、signal／決策。 | AX per-call messaging timeout 與總 deadline 已限制；不能保證外部 App 一定在時間內回覆。active-window CGWindowListCopyWindowInfo 在背景，仍會取得系統提供的整個集合，再處理最多 128 項；可進一步研究更小 metadata 查詢。 |
| logging／通知風暴 | 每次事件 enqueue 可累積磁碟工作；改固定 128 筆／64 KiB、每筆 1,024 bytes、20 筆／秒、1 秒 dedup、單一 drain。檔案 512 KiB rotation 2 份；讀最近 log 有 64 KiB／150 行上限。TIS／hotkey 合併 signal，只排一個工作。 | 滿載丟棄診斷，不能以無界 queue 換完整 log。100,000 次 event storm 已測試。 |
| runtime snapshot／pause | backend、scope、foreground、remote、pause、Secure Input、session、feature flags、settings revision、layout、permissions、generation 統一 value snapshot。InputSource 延遲 startup/retry/verify/cooldown 工作綁 workEpoch；排除其自身 TIS layout acknowledgement，避免自行取消正常切換。 | App 活動、Secure Input、session 等真實事件時序仍需實測；安全條件不因省效能刪除。 |
| Fn/UserKeyMapping 還原 | 原先只存 preferences，crash 可來不及落盤／held key 下改映射。新 private 0600 atomic journal，fsync/F_FULLFSYNC、rename、directory sync；no-follow、owner/type/size 驗證，64 KiB／128 originals 上限，先保存才寫 mapping。按住按鍵時等待 neutral。 | 正常退出還原；force quit、update／reboot 後下次啟動偵測並恢復／調和，不宣稱 SIGKILL 後即時還原。外部工具後續改過 mapping 時保留外部變更，需實機驗收不同 boot／鍵盤 inventory。 |
| update transaction | 私人 staging → payload SHA/codesign/版本/pin 驗證 → switch。保存舊 App/helper/license/pin/plist／原服務狀態；正常失敗 rollback；舊 App 備份最多兩份。 | shared official Driver pkg 不是本 App 私有資產，不做未知版本覆蓋／降級。不同版 fail closed；真正 Driver upgrade、pkg partial install／activation 副作用的完整 rollback 尚未實作／驗收。 |
| update 被中止 | EXIT trap 無法處理 SIGKILL。新 root/private `.install-recovery` data-only journal，先同步 immutable 舊快照，再以 atomic no-clobber hardlink 發布；下次 installer 先恢復。活的 owner PID／不可信 journal 拒絕接管；復原失敗保留 snapshot。App 發現 journal 會停用輸入並顯示重跑 installer／重啟提示。 | private fixture SIGKILL 測試通過；真實斷電、管理員權限、launchd／DriverKit 狀態尚未實測。App 為一次啟動檢查，沒有新增常駐 watchdog 或 polling。 |
| ZIP build／SDK integrity | `git rev-parse HEAD` 不再為唯一來源；無 `.git` 使用 `archive`，不借父目錄 repo。合法 `SOURCE_REVISION` 可覆蓋，非法值拒絕。SDK 即使存在 marker 仍每次驗 archive checksum並從驗證 bytes 重建；header shape 驗證不用可被 `python -O` 移除的 assert。 | 本機真正無 `.git` 的解壓 source build 已納入驗證；Hosted CI 尚未執行本次未提交變更。 |
| packaging／FinderSync | App 只包明確的 BridgePlatform resource bundle 與所需 branding/guide/license。Installer 只複製明確 allowlist。FinderSync 在功能關閉時 directoryURLs 為空；Release 預設 `-O`，保留 `-Osize` 比較選項。 | 不宣稱 macOS 會立刻終止 Finder extension process。SDK/vendor copyright headers 保留；尚未完成可安全裁減的逐檔授權 inventory。 |

### timer 檢查

- App UI／status 由 0.5 秒調成啟用時 1 秒；全關、無限暫停、inactive session、非翻譯 remote role 時停掉。pause/debug 到期用一次性 deadline；waiting-neutral 重用 1 秒檢查。
- EventTap 0.25 秒 safety 與 HID 0.25 秒 heartbeat／Secure Input／session／lease 檢查保留，只在相關引擎啟用時運行；沒有刪除失聯釋放或 safety validation。
- native 鍵盤 inventory 改事件通知；HID discovery callback 加 30 秒低頻備援，取代 2 秒掃描。
- InputSource Secure Input 恢復只有等待時啟動，2 秒逐步 backoff 至 30 秒；stop／失效會取消。
- Screenshot 原有配置檢查是 30 天 one-shot，只在功能啟用時存在。新增 timeout 為每個 job 一次 120 秒、owned child 終止一次 2 秒 escalation；不是高頻輪詢。

## 4. 新增 regression scenarios

主專案從修復前 166 項增加至 208 項（增加 42），保留全部原有 suite。helper 從 11 至 12。另新增 installer／source／SDK 13 項；原有 monitoring 5 項亦執行。

| 使用者要求／補充問題 | 測試入口與驗證 |
| --- | --- |
| Ctrl down → C down → C up → Tab down → Tab up → Ctrl up | `ReleaseInputRegressionTests.copyThenTabRestoresStillHeldControl`，驗實體 Ctrl 延續與最終 neutral。 |
| C 尚未放開再按 Right Arrow | `overlappingChordsRollOverWithoutModifierUnionOrOldKeyResurrection`，同裝置與兩裝置；Command／Option 不合併，不復活舊 C。C++ `ReportTests` 驗報告 rollover。 |
| modifier 不同釋放順序、重複 key-down/up | `leftRightControlAndReleaseOrdersStayBalanced`；`rapidRepeatedInputRemainsBoundedAcrossDevicesAndReleaseOrders` 的 10,000 次輸入；原有 120,000 events stress 仍執行。 |
| 兩鍵盤、disconnect 與 slot 重用 | 上述 overlap／release；`recycledDeviceSlotCannotInheritAnOldShortcutModifierOwnership`。 |
| backend switch、pause/resume、Secure、session、快速 App switch | `policyInvalidationWhileHeldWaitsForNeutral`、runtime policy 多變因矩陣、`EventTapReleaseRegressionTests` 驗 release 一次且送原 PID；既有 lifecycle／event pairing suites。 |
| HID/EventTap ownership | `BackendHandoffRegressionTests`；`BackendOwnershipTests` 真正匿名 NSXPC connection 驗 ACK／timeout gate；pending stop 後 controller 能 deallocate，修正 exported object retain cycle。 |
| Finder Ctrl+X → navigation → Ctrl+V | `finderNavigationKeepsCutButCopyAndClipboardChangeCancelIt`；`FinderCutEpochRegressionTests` 驗導航保存但新 epoch 取消。實際 Finder 剪貼簿 acknowledgement／移動結果仍需驗收。 |
| Finder filename editing／file selection／unknown Delete | `ReleasePlatformRegressionTests` 的 focus decision、filename／sidebar 保守處理；text／unknown 不送刪檔 command。真實 AX hierarchy 不由純政策測試證明。 |
| Screenshot start → pause/backend/session/generation/secure/disable | `ScreenshotRuntimeTests` 呼叫真正 ScreenshotManager，使用 injected driver 與 private pasteboard；舊 completion 不可 commit、single-flight 不能提早重用。 |
| Screenshot cancel／permission／process／disk／decode／encode／timeout | runtime／processing tests；`NativeScreenshotJobTests` 以真正私人 `/bin/sh` child 驗 bounded stderr 四種失敗；`ScreenshotNoninteractiveFailureTests` 驗 unattended missing image。 |
| 圖片預算／大圖／編碼 | image overflow/depth 純政策；偽造有效 PNG header 的 40,000 width 在 decode 前拒絕；真正 ImageIO consumer 32-byte cap 拒絕、4,096 cap 成功並可 decode。 |
| Win+Shift+S／Alt+Print／Win+Print／Print preference | `windowsScreenshotVariantsPairAndRespectPrintScreenPreference`；HID 真正 F13 必須保留而 PrintScreen 觸發的 provenance test。 |
| Remote profile switching／InputSource epoch | `ownershipIsExclusiveAndRemoteRoleIsExplicit`、runtime transitions；`InputSourceWorkPolicyTests` 驗 host 變化失效但自身 layout acknowledgement 不取消。 |
| 慢 logger／MainActor／notification backlog | `BoundedLoggerTests`、`DeferredSignalMailboxTests`、`BoundedActionInboxTests` 各 100,000 次 offer，驗證容量與只排一個 drain；`RuntimeWakeRegressionTests` 驗 inactive/pause/deadline。 |
| mapping durability、symlink／不可寫位置 | `MappingJournalTests` 由獨立 Python process 讀真正 journal；原有 mapper tests 改私人 journal fixture並驗 held-key neutral。 |
| ZIP source build without .git | `test_source_version.py` 3 項＋真正 archive → extract → build-app；驗版本來源 archive，不僅 stub git。 |
| Fresh Driver／already installed／query error | `test_install_backend.py` 以正式腳本 private copy 驗首次安裝、既有同版不重裝、真正查詢錯誤與異版拒絕。 |
| Driver install／upgrade failure rollback | 驗 pkg failure 不改舊 App/helper/service、helper/service switch failure rollback；異版 Driver 拒絕而非執行 upgrade。**沒有把此測試描述成實際 Driver upgrade rollback。** |
| SIGKILL update／live owner／symlink recovery | 在 private fixture 真正 kill installer，再次執行先恢復舊 App/helper/pin/service；活 PID 不接管；symlink journal 拒絕。 |
| SDK marker／optimized Python | `test_hid_sdk_build.py` 驗 marker 不能跳過 archive integrity，`PYTHONOPTIMIZE` 不能移除 header shape 驗證。 |

修復前已為可重現的輸入、首次 installer、slot 重用、F13 alias、XPC 保留、native 截圖失敗等建立失敗案例；需要新注入介面的案例先補 scenario／test fixture，再實作 production API。沒有宣稱每個新增 API 的 compile failure 都是舊 production 語意錯誤。

## 5. 完整測試與建置結果

本機環境：Apple Silicon arm64、macOS 27.0（26A428）、Swift 6.4；部署目標 macOS 14。所有 final log 存在 `build/verification/`，該目錄為 ignored 建置證據，不是 runtime resource。

| 檢查 | 數量／結果 | 證據 |
| --- | --- | --- |
| 主專案 Debug 完整 suite | 208，全部通過：InputSourceCore 34＋BridgePlatform 78＋BridgeCore 96 | `root-debug.log` |
| 主專案 Release 完整 suite | 相同 208，全部通過 | `root-release.log` |
| 主專案 Address Sanitizer 完整 suite | 相同 208，全部通過，無 ASan error | `root-asan.log` |
| HID helper Debug 完整 suite＋build/self-check/sign | 12，全部通過 | `hid-build-debug.log` |
| HID helper Release 完整 suite | 12，全部通過 | `hid-release.log` |
| HID helper Address Sanitizer 完整 suite | 12，全部通過，無 ASan error | `hid-asan.log` |
| Installer／source version／SDK | 13，全部通過 | `installer.log` |
| 原有 resource monitoring tests | 5，全部通過 | `monitoring.log` |
| shell/plist/JSON/workflow/diff | 13 shell syntax、7 plist、1 resource JSON、workflow YAML、git diff --check 通過 | `static-checks.json` |
| Git checkout App Release | build、registry/image self-check、App/Finder strict codesign 通過 | `app-build.log` |
| 無 .git source ZIP | 真正壓縮／解壓後 Release App build/self-check/sign 通過；revision/source state 為 archive | `zip-app-build.log`、`zip-source.json` |
| DMG／HID ZIP | DMG verify、ZIP CRC、PAYLOAD-SHA256SUMS、App/helper/Finder 版本 build 26、strict signature、sidecar checksum 通過 | `artifact-verification.json`、package logs |

**238 項不同測試全數通過**（208＋12＋13＋5）。Debug／Release／ASan 的同一個 test 不重複當成新增 test。Clang／SDK 的既有 deprecated 與工具鏈 link search path warning 不是 failure，log 保留。本機驗證完成時 Hosted GitHub Actions 尚未執行這批變更；後續結果見對應 PR，本機結果不能寫成 Hosted CI 通過。

本次候選產物為 `0.5.14-preflight.5`，App/helper/Finder 版本均為 0.5.14（build 26）。985 筆 payload checksum 通過；包內 App 與目前簽章建置的所有檔案 bytes 相同。development ad-hoc 簽章，未公證，沒有發行或安裝。

| 產物 | bytes | SHA-256 |
| --- | ---: | --- |
| [WindowsMacBridge-0.5.14-preflight.5-macos-arm64.dmg](../build/download/WindowsMacBridge-0.5.14-preflight.5-macos-arm64.dmg) | 1,300,813 | `bc4748043498af5e494b92e7d626f09e5d94ca9730668a163c75bf4da5afc51d` |
| [WindowsMacBridge-0.5.14-preflight.5-macos-arm64.zip](../build/download/WindowsMacBridge-0.5.14-preflight.5-macos-arm64.zip) | 5,482,965 | `aa142c063aa2a0c7fe2590571caba3815cd2868fc0e04784334fdcc9e3c25ec7` |

詳細驗證：[artifact-verification.json](../build/verification/artifact-verification.json)；來源與 log digest：[manifest.json](../build/verification/manifest.json)。

## 6. 最後跨模組 code review

| 要求 | Review 結果／邊界 |
| --- | --- |
| 無新的 retain cycle／無界集合 | 修正 NSXPCConnection → exported controller 的實際循環，以 weak receiver 替代。所有新增輸入、動作、log、notification slots 有上限；測試真實 XPC controller deallocation。不能將 ASan 稱為完整 leak proof。 |
| 無新的無界 queue | IPC ingress 16、AX action 16、一個 drain／worker；截圖一個 job；notification coalesced bitmask；log 一個 drain／容量限制。外部 framework 自有 queue 不在本程式控制內。 |
| 無新的高頻 timer | 新增 timeout／deadline 皆一次性；保留 safety lease，降低非安全 polling。詳見 timer 清單。 |
| keyboard hot path 無同步慢工作 | EventTap／HID callback 不做 AX traversal、檔案／shell／bitmap／UI。callback 的 state lock 與 stderr I/O lock 分開，Esc cancellation 不等 stderr read。慢工作於 callback 外且數量有界。 |
| HID/EventTap 不 double translate | exclusive backend＋stop ACK gate＋synthetic marker；HID screenshot 不開 second tap。這保證本程式 ownership 政策，不取代其他 remapper 共存或真實裝置驗收。 |
| backend/UI/runtime 一致 | 單一 publish transition，同一 immutable generation；停舊 backend 後再交接。permission／preset／resume/start 皆走相同流程；journal 未復原時 fail closed。 |
| pause／Secure／session／disconnect release | ledger invalidation、original PID release、helper reset／neutral、epoch cancel 皆保留。Secure Input 下禁止 synthetic injection；真實系統持鍵切換的安全釋放效果需實測。 |
| Finder unknown focus 不誤刪 | unknown/text 永遠不能送 trash modifier；AX selection 不明則保留原生 Delete。cut intent 不能跨 epoch 復活。 |
| 截圖 memory | predecode budget＋single-flight＋PNG fast path＋bounded encoder，無 eager TIFF 重複 bitmap。codec 內部峰值與實際 RSS 不作硬上限保證。 |
| installer/update recovery | 正常錯誤 rollback 與 SIGKILL 後下一次 recovery 已用 private fixture驗；不可信／live owner拒絕。共享 Driver pkg／activation 完整回復仍有限制。 |
| clone／ZIP build | 兩種 source build 都實際執行；`archive` fallback 和 explicit hex override 都有測試。 |

Alt+Tab 搜尋涵蓋 source、helper、extension、settings、IPC、tests 與目前指南。沒有自製 switcher/MRU/thumbnail/AXObserver lifecycle。剩餘 Alt+Tab 文字是 native macOS／Remote Client 的操作說明；歷史審查文件保留歷史證據並加上「以本修復報告為準」標示。原生 Option/Command keyboard normalization 不等於自製 Alt+Tab，沒有為清除舊功能破壞這些 modifier 設定。

## 7. 剩餘 P0／P1 與 macOS 實機驗收

**已重現並可由自動測試驗證的上述 P0 程式缺陷已修正；仍不能確認整體零 P0。** 以下是正式上線門檻，尚未取得實體／真實授權證據：

1. USB／Bluetooth、MacBook 內建、兩把外接、左右 modifier、任意釋放順序、拔線／重連，尤其 Ctrl+C 持 Ctrl 再 Tab、C 未放開再 Right Arrow；於 EventTap/HID 分別驗證。
2. 按住 Ctrl/Shift/Alt 切 backend、pause/resume、Secure Input、睡眠／喚醒、登入／鎖定、快速 App 切換；驗沒有 stuck synthetic key，HID stop acknowledgement 在真實 Driver 報告傳輸下正確。
3. Universal Control 兩端切換、內建／外接混用、按住 modifier 跨裝置；Windows→Mac、Mac→Mac、兩端都裝 Bridge 依 remote role 驗一次翻譯，包含 Remote Client 全螢幕／剪貼簿設定。
4. Finder 各 view、filename editing、搜尋欄、Go To Folder、sidebar、空資料夾、未知 AX focus：Delete 不誤刪；Ctrl+X 導航後 Ctrl+V 真正移動；cut timeout／Clipboard change／pause 不復活。
5. Alt+F4 在有未儲存文件、多視窗、自製 close button／無 close button 的 App 保留原本提示，不 quit App。
6. screenshot 真實 Screen Recording permission denied／撤回、Esc cancel、磁碟不可寫、active-window、多螢幕大圖；capture 後 pause／backend／session／Secure 變化不寫 Clipboard；實測峰值與延遲。
7. 真正 fresh Driver install、同版已安裝、helper/service bootstrap fail、更新中止／斷電後 recovery；DriverKit activation、TCC、共享其他工具的 Driver 共存，含系統版本最低 macOS 14。
8. Fn/UserKeyMapping 正常退出、force quit、更新、reboot 後下一次啟動復原，以及外部工具改映射後不覆蓋外部新設定。

**仍存在的 P1 限制：**

- HID 不安全／不支援的複合 descriptor 維持 native，缺少 Windows 行為；沒有可靠 EventTap device ID 時不能安全用盲目 hybrid 補齊。不能宣稱「任意外接鍵盤全部支援」。
- Remote／UC input provenance、混合來源鍵盤的 Win modifier、EventTap 的 F13／PrintScreen alias 仍需手動配置／實測；自動雙端協議尚不存在。
- 真正共用 Driver upgrade rollback 尚未完成：不同版本拒絕更新；官方 pkg 的 partial install／activation 影響無法由 App/helper snapshot 全部撤銷。測試只證明自有 App/helper/service 狀態復原。
- `NSPasteboard.clearContents()` 後 `writeObjects` 失敗無法以公開 API 原子還原舊 payload。本程式不讀先前 Clipboard 內容；這種 commit failure 會回報、保留截圖檔，但不能保證既有 Clipboard 不變。取消／permission／process／decode／encode failure 在 commit 前不改 Clipboard。
- ImageIO／PDF 內部配置和真實 CPU/RAM peak 尚未量測。現有 budget 抑制受輸入控制的 dimension／pixel／本程式 buffer，不能聲稱任意惡意 codec 資料都絕不產生內部配置峰值。

所以本次只能交付修復候選版，**沒有正式上線判定**。也沒有把 failed-closed 的功能覆蓋限制描述成全部 P1 完成。

## 8. CPU／RAM／程式體積與下一步

本次已降低不必要 UI polling、keyboard inventory polling、notification backlog、log backlog、圖片重複編碼及 runtime resource duplication；安全 lease、Secure Input、session/generation 與失聯 release 保留。

Finder Release 本輪實際比較：未簽章 `-O` 92,568 bytes，`-Osize` 95,920 bytes；`-O` 小約 3.5%，所以預設使用 `-O`。簽章 Finder binary 92,640 bytes。主 App 25 files 共 3,141,934 bytes（約 3.0 MiB），主執行檔 2,863,776 bytes，helper 1,737,232 bytes。見 [finder-optimization.json](../build/verification/finder-optimization.json) 與 [artifact-verification.json](../build/verification/artifact-verification.json)。這是檔案體積證據，不是 CPU／RAM benchmark。本候選版未在真實常駐輸入狀態量測 CPU、wakeups、physical footprint 或大圖 peak；不能沿用舊版本的 idle 數字。

後續可在不犧牲可靠性下：

- 在真實 idle／高頻輸入／AX timeout／HID reconnect／大圖截圖下量測 wakeups、p95 延遲與 physical footprint，再決定 safety-independent 的合併輪詢；不要降低 heartbeat／session／Secure safety coverage。
- active-window metadata 若有可靠官方窄查詢，可降低取得整個 WindowServer collection 的配置；保持背景 worker／single-flight／deadline。
- 為 SDK/vendor headers 建立逐檔 copyright/license inventory，確認哪些只需保留 notice，才裁減安裝包的非 runtime headers。現有 header notices 約 8 MiB，未驗證前不移除授權文字。
- FinderSync 按需 directory observation 已實作，可測 macOS 的 process 啟動／idle 行為後再評估註冊方式；不要宣稱關閉 toggle 已保證 process 消失。
- screenshot alternate representation 若日後因 App 相容性需要 TIFF，採 lazy provider 並沿用相同 budget；目前 PNG 已避免 eager second bitmap。
- shortcut table 共用／compact 放低優先，避免為少量檔案體積增加 ownership／modifier 邏輯複雜度。

## 完整修改檔案清單

<!-- GENERATED_CHANGED_FILES -->

共 76 個修改／新增檔案。

- [.github/workflows/macos.yml](../.github/workflows/macos.yml)
- [Docs/Architecture.md](../Docs/Architecture.md)
- [Docs/HIDIntegration.md](../Docs/HIDIntegration.md)
- [Docs/KarabinerReplacement.md](../Docs/KarabinerReplacement.md)
- [Docs/PreReleaseRepair-2026-09-30.md](../Docs/PreReleaseRepair-2026-09-30.md)
- [Docs/ProjectIntegration.md](../Docs/ProjectIntegration.md)
- [Docs/ReleaseAcceptance.md](../Docs/ReleaseAcceptance.md)
- [Docs/ReleaseReadiness-2026-09-28.md](../Docs/ReleaseReadiness-2026-09-28.md)
- [Docs/SafetyAndUsabilityReview.md](../Docs/SafetyAndUsabilityReview.md)
- [Docs/Validation.md](../Docs/Validation.md)
- [Extensions/FinderSync/FinderSync.swift](../Extensions/FinderSync/FinderSync.swift)
- [Extensions/FinderSync/Info.plist](../Extensions/FinderSync/Info.plist)
- [README.md](../README.md)
- [Resources/AcceptanceGuide.md](../Resources/AcceptanceGuide.md)
- [Resources/Info.plist](../Resources/Info.plist)
- [Resources/Installer/HIDHelper-Info.plist](../Resources/Installer/HIDHelper-Info.plist)
- [Resources/Installer/InstallBackend.sh](../Resources/Installer/InstallBackend.sh)
- [Resources/Installer/READ-ME-FIRST.md](../Resources/Installer/READ-ME-FIRST.md)
- [Resources/UserGuide.md](../Resources/UserGuide.md)
- [Sources/BridgeCore/BackendCapabilities.swift](../Sources/BridgeCore/BackendCapabilities.swift)
- [Sources/BridgeCore/BoundedActionInbox.swift](../Sources/BridgeCore/BoundedActionInbox.swift)
- [Sources/BridgeCore/BoundedDiagnosticLogger.swift](../Sources/BridgeCore/BoundedDiagnosticLogger.swift)
- [Sources/BridgeCore/DeferredSignalMailbox.swift](../Sources/BridgeCore/DeferredSignalMailbox.swift)
- [Sources/BridgeCore/FinderActionPolicy.swift](../Sources/BridgeCore/FinderActionPolicy.swift)
- [Sources/BridgeCore/FinderCutState.swift](../Sources/BridgeCore/FinderCutState.swift)
- [Sources/BridgeCore/FinderPathSelection.swift](../Sources/BridgeCore/FinderPathSelection.swift)
- [Sources/BridgeCore/HIDTranslationEngine.swift](../Sources/BridgeCore/HIDTranslationEngine.swift)
- [Sources/BridgeCore/ImageMemoryBudget.swift](../Sources/BridgeCore/ImageMemoryBudget.swift)
- [Sources/BridgeCore/KeyboardEventProcessor.swift](../Sources/BridgeCore/KeyboardEventProcessor.swift)
- [Sources/BridgeCore/Model.swift](../Sources/BridgeCore/Model.swift)
- [Sources/BridgeCore/RuntimePolicy.swift](../Sources/BridgeCore/RuntimePolicy.swift)
- [Sources/BridgeCore/ScreenshotCaptureLifecycle.swift](../Sources/BridgeCore/ScreenshotCaptureLifecycle.swift)
- [Sources/BridgeCore/ScreenshotShortcuts.swift](../Sources/BridgeCore/ScreenshotShortcuts.swift)
- [Sources/BridgePlatform/FinderModePublisher.swift](../Sources/BridgePlatform/FinderModePublisher.swift)
- [Sources/BridgePlatform/HIDBackendClient.swift](../Sources/BridgePlatform/HIDBackendClient.swift)
- [Sources/BridgePlatform/InputEngine.swift](../Sources/BridgePlatform/InputEngine.swift)
- [Sources/BridgePlatform/KeyboardMappingDiagnostics.swift](../Sources/BridgePlatform/KeyboardMappingDiagnostics.swift)
- [Sources/BridgePlatform/MacBookKeyboardMapper.swift](../Sources/BridgePlatform/MacBookKeyboardMapper.swift)
- [Sources/BridgePlatform/NativeMacBookKeyboardBackend.swift](../Sources/BridgePlatform/NativeMacBookKeyboardBackend.swift)
- [Sources/BridgePlatform/PrivateMappingJournal.swift](../Sources/BridgePlatform/PrivateMappingJournal.swift)
- [Sources/BridgePlatform/ScreenshotCaptureDriver.swift](../Sources/BridgePlatform/ScreenshotCaptureDriver.swift)
- [Sources/BridgePlatform/ScreenshotManager.swift](../Sources/BridgePlatform/ScreenshotManager.swift)
- [Sources/BridgePlatform/ScreenshotShortcut.swift](../Sources/BridgePlatform/ScreenshotShortcut.swift)
- [Sources/BridgePlatform/SettingsStore.swift](../Sources/BridgePlatform/SettingsStore.swift)
- [Sources/BridgePlatform/ShortcutActionDispatcher.swift](../Sources/BridgePlatform/ShortcutActionDispatcher.swift)
- [Sources/HIDProtocol/HIDProtocol.swift](../Sources/HIDProtocol/HIDProtocol.swift)
- [Sources/InputSourceSupport/FileLogger.swift](../Sources/InputSourceSupport/FileLogger.swift)
- [Sources/InputSourceSupport/GuardController.swift](../Sources/InputSourceSupport/GuardController.swift)
- [Sources/InputSourceSupport/HotkeyManager.swift](../Sources/InputSourceSupport/HotkeyManager.swift)
- [Sources/InputSourceSupport/InputSourceCoordinator.swift](../Sources/InputSourceSupport/InputSourceCoordinator.swift)
- [Sources/WindowsMacBridge/BridgeController.swift](../Sources/WindowsMacBridge/BridgeController.swift)
- [Sources/WindowsMacBridge/SettingsView.swift](../Sources/WindowsMacBridge/SettingsView.swift)
- [Tests/BridgeCoreTests/BoundedLoggerTests.swift](../Tests/BridgeCoreTests/BoundedLoggerTests.swift)
- [Tests/BridgeCoreTests/HIDTranslationTests.swift](../Tests/BridgeCoreTests/HIDTranslationTests.swift)
- [Tests/BridgeCoreTests/ReleaseInputRegressionTests.swift](../Tests/BridgeCoreTests/ReleaseInputRegressionTests.swift)
- [Tests/BridgeCoreTests/ReleasePolicyRegressionTests.swift](../Tests/BridgeCoreTests/ReleasePolicyRegressionTests.swift)
- [Tests/BridgePlatformTests/BackendOwnershipTests.swift](../Tests/BridgePlatformTests/BackendOwnershipTests.swift)
- [Tests/BridgePlatformTests/MacBookKeyboardMapperTests.swift](../Tests/BridgePlatformTests/MacBookKeyboardMapperTests.swift)
- [Tests/BridgePlatformTests/MappingJournalTests.swift](../Tests/BridgePlatformTests/MappingJournalTests.swift)
- [Tests/BridgePlatformTests/NativeScreenshotJobTests.swift](../Tests/BridgePlatformTests/NativeScreenshotJobTests.swift)
- [Tests/BridgePlatformTests/ReleasePlatformRegressionTests.swift](../Tests/BridgePlatformTests/ReleasePlatformRegressionTests.swift)
- [Tests/BridgePlatformTests/ScreenshotRuntimeTests.swift](../Tests/BridgePlatformTests/ScreenshotRuntimeTests.swift)
- [Tests/BridgePlatformTests/ScreenshotTests.swift](../Tests/BridgePlatformTests/ScreenshotTests.swift)
- [Tests/BridgePlatformTests/SettingsStoreTests.swift](../Tests/BridgePlatformTests/SettingsStoreTests.swift)
- [Tests/InstallerTests/test_hid_sdk_build.py](../Tests/InstallerTests/test_hid_sdk_build.py)
- [Tests/InstallerTests/test_install_backend.py](../Tests/InstallerTests/test_install_backend.py)
- [Tests/InstallerTests/test_source_version.py](../Tests/InstallerTests/test_source_version.py)
- [Tools/HIDBackend/Sources/BridgeHIDHelper/DeviceCapture.swift](../Tools/HIDBackend/Sources/BridgeHIDHelper/DeviceCapture.swift)
- [Tools/HIDBackend/Sources/VirtualHID/VirtualHID.cpp](../Tools/HIDBackend/Sources/VirtualHID/VirtualHID.cpp)
- [Tools/HIDBackend/Sources/VirtualHID/include/VirtualHID.h](../Tools/HIDBackend/Sources/VirtualHID/include/VirtualHID.h)
- [Tools/HIDBackend/Tests/VirtualHIDTests/ReportTests.swift](../Tools/HIDBackend/Tests/VirtualHIDTests/ReportTests.swift)
- [scripts/build-app.sh](../scripts/build-app.sh)
- [scripts/build-hid-helper.sh](../scripts/build-hid-helper.sh)
- [scripts/package-hid-release.sh](../scripts/package-hid-release.sh)
- [scripts/prepare-hid-sdk.py](../scripts/prepare-hid-sdk.py)
- [scripts/source-version.sh](../scripts/source-version.sh)
