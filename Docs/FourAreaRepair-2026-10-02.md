# 四方向檢查修復：0.5.17（29）

日期：2026-10-02。來源基準 `07101539e4663d7cb435e9cf7b152d44cc790d1e`，含前輪與本輪未提交的修正。本報告接續 ComplexityHandoff / ConsistencyRepair，不把先前版本的測試或安裝當成新版結果。開始前已保存 tracked patch 與 untracked archive 到 `build/four-area-review/`。

**程式修復、測試及可安裝候選包已完成；兩台 Mac 的實體輸入、更新後 GUI 授權與實際 Driver 安裝回復仍待驗收。未改動已安裝 0.5.15，也未修改 TCC／Driver 或一般剪貼簿。** 本輪曾以系統 screencapture 產生一張暫存圖，僅核對 Apple 截圖 metadata，隨即刪除；沒有展示或留存畫面內容。

## 四項結果

1. **跨機來源／目的端**：重新檢查 source raw HID、annotated recipient gate、Remote producer ledger 與 already-translated 規則。新增回歸重現：registry 已撤銷 producer，但 callback 尚持有舊 snapshot 時，UC 仍被分類為可處理來源。現在分類入口即檢查原子 work gate，舊快照回 unknown，阻止 UC 繞過 Remote router 的第二層撤銷檢查。目的端 Terminal／文字 App 的語意及 source 不執行 Finder／AX 等既有回歸持續通過。
2. **多鍵盤／持鍵**：新增兩鍵盤 Ctrl／Shift／Alt 的 720 種放鍵順序，每一步核對剩餘的真實 modifier；另測安全中斷／斷連的 48 個放鍵序列，確認舊快捷鍵不復活、釋放完後新的 Ctrl+C 能正常執行。原有 100,000／120,000-event stress、App continuity、Pause、backend handoff、Secure Input、lease 等完整 suite 通過。這些仍是模型／production core 證據，不能替代硬體事件順序。
3. **權限／共用 Driver／回復**：保留真正 CGRequestPostEventAccess／AX request 和重新 preflight 的流程。新增回歸重現：deactivate 回傳 0，但 systemextensionsctl 仍有 active 或 pending-reboot registration 時，fresh rollback 過早移除 manager、receipt 與復原 journal。現在必須確認 registration 已消失才能完成回復；否則保留 manager／receipt／snapshot，且不重新啟動半套服務。相容共用 Driver 不重啟、未知版本不盲升級的保護仍在。沒有實際執行管理員安裝或替使用者核准 OS 提示。
4. **截圖／記憶體**：新增原生 ⌘⇧3／⌘⇧4 完成存檔後自動複製，不需點開縮圖；保留 macOS 選區、空白鍵選視窗與跨機按鍵路由。補強 PDF 父 Pages 繼承 Resources 的漏洞，避免 oversized raster 躲過 leaf-page preflight。補上真正 manager 成功寫入可貼上的 PNG、解碼途中 Pause→resume、native 圖片切到貼上 App 後完成、真實 FSEvents callback 只複製一次／stop不重播的回歸。

Karabiner 參考範圍：官方 [DEVELOPMENT.md](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md) 說明 HID per-device 與 CGEventTap 缺少來源 device ID、Secure Input 限制。採目的端語意及原始鍵流設計，不宣稱 Karabiner 提供了跨機目的 App 的公開識別 API。此次並未將任何 UC／Remote transport 標為 Verified。

## 原生截圖實作與邊界

`NativeScreenshotObserver` 以 FSEvents 監看目前截圖目錄，不攔截系統 ⌘⇧3／4、不改 macOS 截圖設定、不輪詢／掃描歷史圖片。只接受啟用後的新 regular file、已知圖片格式、Apple `kMDItemIsScreenCapture` Boolean metadata、檔案大小上限；排除 symlink 與 Bridge 自己產生的檔名。metadata 探查最多一個背景工作、64 個候選，去重記錄上限 32；圖片處理仍 single-flight，另保留至多一張最新待處理 native 圖片。

停用、Pause、session/backend/permission/settings 安全中斷會撤銷 observer generation 與舊圖片工作；新工作不和未結束的舊解碼重疊。普通本機 App 切換則讓已完成的 native 截圖繼續複製，方便切到目的 App 貼上；Terminal／IDE 的原生截圖同樣可自動複製，Remote／VM／Game／disabled profile 仍停止本機增強。使用 native 已產生圖片不需另一次螢幕錄製要求；Bridge 自己啟動 screencapture 的路徑仍檢查錄製權限。

浮動縮圖會延後系統存檔，所以可能等縮圖消失才可貼上。Win+Shift+S 仍是框選完成直接儲存／複製。選系統「剪貼簿」由 macOS 自己處理；Preview／Mail 等不產生被觀察目錄新檔的目的地不在此路徑。變更系統存檔目錄後須重新開關截圖功能。這是對本機新截圖檔的補助，並非任意 screenshot utility 的 global clipboard hook。

原生截图 UI 的生命週期由 macOS 管理。若在 Pause 中仍保留系統框選 UI，恢复後才真正完成拍攝並建立檔案，會視為新的檔案事件；Bridge 不會替系統取消那個 UI。已進入 Bridge 的旧圖片工作仍不能恢復並覆寫 Clipboard。

## 最新驗證

| 檢查 | 結果 |
|---|---|
| Root Release | 292 項：Core 142、Platform 116、InputSource 34 |
| Helper build / tests / self-check | 15 項通過；protocol 7、driver ABI 1.8.0 |
| Installer Python/native fixtures | 31 項通過 |
| Monitoring | 5 項通過 |
| 合計 distinct suite tests | 343 項；參數序列及 ASan 不重複灌入總數 |
| 最新 ASan 針對 screenshot／source revocation／多鍵盤 | 43 項通過，無 AddressSanitizer error |
| arm64 App / helper / bounded runner | build、self-check、strict codesign 通過 |
| DMG / HID ZIP | 封裝完成、DMG verify 與 payload checksum 通過 |
| 靜態檢查 | git diff --check、相關 shell syntax 通過 |
| Hosted CI / commit / push | 本輪未執行；所有前輪與本輪來源仍在工作目錄 |

原始 log：`build/four-area-review/{root-final,helper-build,installer-final,monitoring,asan-final,app-build,package-dmg,package-hid}.log`。最初失敗重現另存 `regression-red.log` 與 `installer-red.log`。source-sha256.json 留存來源雜湊。

## 36MP 圖片測量

對自行產生的 6000×6000 fixture 執行真正 ScreenshotImagePreparation → 私有 named NSPasteboard → NSImage → CGContext.draw，強制貼上端建立 raster；只取得 lazy CGImage 的測量不列入。未讀寫使用者一般剪貼簿。

| 格式 | 最大 RSS | peak physical footprint | 處理時間 |
|---|---:|---:|---:|
| PNG | 433.44 MiB | 281.36 MiB | 0.162 s |
| TIFF | 573.11 MiB | 421.03 MiB | 0.406 s |
| PDF | 436.27 MiB | 284.13 MiB | 0.471 s |

仍是獨立 benchmark process 的峰值，未加總 GUI App、screencapture、WindowServer、pboard daemon 及其他貼上 App。144 MiB decoded-image guard 不代表全系統／全程序上限。PNG 路徑不在 Bridge 裡先製作 TIFF，PDF inherited XObjects／form／inline／mask 及 pixel／encoded／decoded budgets 保持檢查。Native codec／ICC／複雜文件的額外配置仍不能靠這份數字當成硬性記憶體保證。

## 交付與接續

- App DMG：`build/download/WindowsMacBridge-0.5.17-preview.1-macos-arm64.dmg`。
- 雙機測試用完整 App/helper/Driver ZIP：`build/download/WindowsMacBridge-0.5.17-preview.1-macos-arm64.zip`。兩者各有 `.sha256`。
- [兩台 Mac 安裝與逐步驗收](../Resources/TwoMacAcceptance.md)，同一份指南也放在 ZIP 根目錄及 App Resources。

MacBook 目前已開 UC 但尚未安裝 Bridge。下一步依指南讓兩台使用同版，再由使用者操作實體鍵盤驗收；特別是來源 Terminal → 目的 TextEdit、雙端 Bridge、持鍵跨機、不同 Remote 軟體、GUI grant/revoke、共用 Driver 與重開機回復。現在不能宣稱四大方向的所有實機組合都已完成驗收。
