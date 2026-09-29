# 0.4.2-preview.1 拖曳安裝版（2026-09-28／29）

- 使用者不申請付費 Developer ID，改為免費個人測試版；ad-hoc 簽章與無公證仍如實揭露。
  DMG 只有 App、Applications 捷徑與開始使用說明，不需要 Install.command 或 Driver。
  原生系統權限／Gatekeeper 提示無法省略；未關閉系統保護或清除 quarantine。
- 新增首次授權說明、收合進階 HID 設定、內建實機驗收指南。既有偏好保留。
  修正文案：EventTap 保留 Alt+Tab，使用原生 Command+Tab 切 App；完整 Alt+Tab
  僅在選用 HID 路徑提供，不能把普通 DMG 宣稱為完整 Karabiner 替代。
- EventTap Ctrl+Y 先放 Ctrl、Y 仍按住時，原本 repeat 可能變成無修飾的 Z。
  三個新測試先得到 5 個失敗，再修正為停止該次按鍵的後續 repeat；仍保留配對 key-up，
  重按 modifier 不會復活連發。覆蓋兩個 Ctrl 與缺失 flagsChanged 的情境。
- 主程式／核心完整 **91 tests 通過**（52 core、20 platform/AppKit、15 input-source、4 migration）。
  包含 120,000+ 事件與 100,000 步雙鍵盤交錯壓測。另有 **36 個鍵盤／HID ASan tests 通過**，
  執行於加入最後兩個 Safari 回歸測試之前；不得將它寫成全 91 tests 都跑過 ASan。
- Safari 回歸在已同步 modifier 狀態下驗證原生 Control+Command+F、Command+M、Fn+F、
  Command+Option+Escape 保留，以及翻譯 Copy 完整放開後普通播放器鍵保留。
  這是程序內事件測試，不向使用者的 App 注入全域測試鍵。
- 設定頁由 TabView 改為 segmented Picker，排除原 CoreUI bundle 查找警告及切頁發布狀態警告。
  負尺寸 fault 以符號化 stack 定位到 macOS 27 的 NSThemeFrame 分享指示器；
  108 筆原程式／無鍵盤測試 App fault 路徑一致。沒有隱藏日誌或修改 private API。
  詳見 [調查記錄](macOS27-UIInvestigation.md)，不可宣稱 macOS 系統警告全部消失。
- Release build、App strict codesign、registry 28 項 self-check、shell syntax、diff whitespace 通過。
  DMG 唯讀掛載後 App signature／self-check 通過，Applications link 正確，內建兩份指南存在，
  executable 與指南逐位元比對 /Applications 安裝版相同。
- DMG 906,059 bytes，SHA-256 `3c7fed1eb90bf3fab8f7e285cbd714cb5f808623759d7e8f74a07f8c924ae9c1`。
  0.4.2 build 8 已放入 /Applications。2026-09-29 使用者完成系統驗證後重新加入本 App，
  正常重啟後 Accessibility 已授權、event posting/listening 可用、EventTap Active、Secure Input OFF。
- 本機授權後以介面自動化完成 Safari 對照：工具 Active 與正常結束（確認程序不存在）時，
  綠色按鈕均能進入視窗全螢幕，選單顯示「離開全螢幕」並可退出；YouTube 聚焦播放器後
  F 均能進入播放器全螢幕。Active 時 Escape 退出、結束工具時播放器退出按鈕操作成功。
  Active 時原生 Control+Command+F 亦切入 Safari 視窗全螢幕。動畫結束後確認返回標準視窗。
  **這是引擎運作期間的 UI 共存測試：自動化按鍵沒有增加 EventTap 的處理／翻譯計數（0/0），
  因此不是實體按鍵經攔截引擎的端到端驗收。** 原回報的嗶聲未重現，根因仍未確定，
  不將上述結果宣稱為修復了原故障。初查曾取消開啟 Codex 的對話框，沒有自動允許網站權限。
- 同一授權後程序的設定頁依序切換八次；限定該 PID 的 15 分鐘日誌查詢未找到 CoreUI、
  Publishing changes 或 negative size 訊息。這是本次操作結果，不推翻先前已重現的 AppKit
  分享指示器警告。測試後恢復 App 背景執行，確認 EventTap Active、Secure Input OFF、短期診斷關閉。
- artifact source `01c03444f199d3e2b993b82eb1ef0268ef30f745` 的 GitHub Actions
  [run 36503942520](https://github.com/steven87090799/WindowsMacBridge/actions/runs/36503942520)
  主程式／DMG job（91 tests）與獨立 HID 打包 job（11 helper tests）皆成功。
- 0.4.2 授權後關閉設定視窗的 **60 秒短期**背景樣本（2026-09-29 01:18:02–01:19:02 UTC）：
  5 筆／每 15 秒，同一 PID 57646；CPU time 1.29 → 1.33 秒，增量 0.04 秒，
  平均單核心 CPU 0.067%。RSS 130.27 → 105.78 MiB、最大 130.27 MiB；
  `vmmap` physical footprint 起迄皆 48.9M（保留工具原單位）。採樣程序已正常結束。
  此樣本主要閒置，不代表三小時、實體高頻輸入或長期記憶體驗收。
- 真實遠端依使用者要求延後，驗收流程已附在 App。實體鍵盤、IME 組字、HID、睡眠／故障恢復
  仍需逐項記錄；上一版的三小時閒置數據不能當成本版本的新三小時驗收。

以下保留歷史版本結果。

---

# 0.3.0-preview 驗證紀錄

日期：2026-09-27。本機 arm64、Swift 6.4 / macOS 27 SDK，deployment target macOS 14。

- 完整 `bash scripts/test.sh` 通過 61 tests（33 BridgeCore、9 Platform/AppKit、15 input-source core/policy、4 migration），追加的 `--filter ActionDispatcherTests` 2 tests 通過；合計 63 項。參數化案例另計。
- 原始 78 條 fixture 中 66 個不同 shortcut inputs 的 keycode/modifier/輸出與白名單 action 對照通過；#63 由 Finder cut state 測試覆蓋。沒有將裝置限定或消費鍵宣稱為已接通。
- 120,000 個 copy down/up 與額外 120,000+ browser modifier/down/repeat/up 混合事件，ledger 最後歸零。這是純核心測試，不是實體輸入 CPU/RSS/延遲的測量。
- HID ledger 驗證六種交換、左右 Shift、双裝置共同持有、拔除只釋放自身、切 Remote 釋放輸出並等待 neutral、容量上限及虛擬輸出未 ready 時禁止 seize。此 ledger 尚未連接裝置／driver。
- Release App 建置、ad-hoc codesign strict verify、包內 registry/scopes 載入 `--self-check` 通過。
- 獨立 `bash scripts/build-hid-helper.sh`：VirtualHID client release build、10 項離線 report/lifecycle tests 及 helper `--self-check` 通過（與 App 的 63 項分開）。額外 100,000 次 report 編碼，不連 driver、不注入事件。官方 8.6.0.pkg 簽署／公證 metadata 檢查通過；沒有安裝。
- `--diagnose-backend` 沒有開 tap、open/seize 裝置或注入事件；本次列出 0 個可見 keyboard service，因此沒有取得真實雙鍵盤／內建鍵盤識別驗證。0 並非不存在鍵盤的證明。
- Info.plist 與 git diff whitespace 檢查通過。CLT 缺少可選 framework search path 的 linker warnings 未阻止建置。

未執行真實 Finder 移動/刪除、鎖定畫面、Global Event Tap、IME composition、Remote/VM session、Secure Input、root helper 或 DriverKit 裝置攔截。不以單元測試取代這些驗收。未更動 Karabiner、登入項目、輸入法偏好或系統鍵盤設定。

HID helper/IPC/driver 安裝整合與 #4/#5–10/#77/Alt+Tab 仍未完成；這是部分功能預覽，不是完整替代版。詳細界線见 [KarabinerReplacement.md](KarabinerReplacement.md)。Hosted CI 需以 PR 的實際 head 結果另行確認。

---

# 0.2.0 整合版驗證紀錄

日期：2026-09-26～27。Swift 6.4 / arm64 / macOS 27.0 (26A428)，deployment target macOS 14。

- `bash scripts/test.sh`：43 tests 通過（19 keyboard core、5 platform/AppKit、15 input-source core/policy、4 migration）。Parameterized tests 另外覆蓋 7 個 Profile cases。
- 原有 120,000 keyboard events 配對壓測與 9 組程序內 AppKit 選單 action 回歸通過；增加輸入來源切換後按住 Ctrl 不提前恢復翻譯的測試。
- 上游 10 項 GuardStateMachine XCTest 情境轉為 Swift Testing；加入 Remote/VM/Game/Disabled、全域 Pause、session、舊版衝突和偏好白名單驗證。
- Release `.app` build、ad-hoc codesign／strict verification 通過；包含原模組 MIT 授權；包內 Registry 27 項通過 `--self-check`。
- `--diagnose-input-sources` 正確發現已安裝的 vChewing-CHT 與 ABC；只列 metadata，没有選來源或啟動 tap。
- UI smoke：四個設定頁存在，唯音頁顯示舊版 VChewingGuard 執行中的阻擋、切換按鈕 disabled、快捷鍵未註冊；更新診斷顯示來源資訊與 0 次切換。Windows Mode、guard、hotkey、登入項目皆未啟用。
- 重複執行 packaged executable 正常 exit 0；只保留一個 WindowsMacBridge process。
- Info.plist、shell syntax、git diff whitespace 檢查通過。

未授予新 Accessibility/Input Monitoring 權限，未替使用者修改輸入法、登入項目或舊版設定。未執行真實全域 tap、Carbon hotkey 消耗、遠端 session、IME composition、Secure Input/sleep 故障注入或長時間 soak。CI workflow 已納入 repository；本機結果不代表 Hosted CI 已通過。

以下保留初版驗證記錄，作為整合前基線。

---

# 0.1.0 開發預覽驗證紀錄

日期：2026-09-26。環境：本機 arm64、Swift 6.4、Command Line Tools、macOS 27 SDK；deployment target 為 macOS 14。

## 通過

- `bash scripts/test.sh`：23 個 Swift Testing tests（18 core、3 platform、2 AppKit）。
- Core stress：60,000 組 down/up，共 120,000 個 shortcut events；最後 press ledger 為空。
- AppKit：人工 CGEvent 經正式 EventRewriter，再轉 NSEvent，9 組快捷鍵全部命中程序內 NSMenu action，包括 Ctrl+Y → Cmd+Shift+Z。
- `bash scripts/build-app.sh`：Release build、ad-hoc codesign、strict signature verification。
- 打包後 `--self-check`：從 App 包內載入 27 項 registry，不啟動 Event Tap。
- 動態依賴檢查：只有系統 framework／Swift runtime，無工作區 dylib 依賴。
- UI smoke：一般／App 規則／診斷頁面可開啟；最新版原生選單出現。未授權且預設停用時，診斷為 Event Tap Inactive、processed/translated 0/0。
- Shell syntax、Info.plist 格式及來源 whitespace 檢查。

## 未驗證／未實作

- 尚未授予 App Accessibility/Input Monitoring，未測實體鍵盤經全域 Event Tap 的端到端流程。
- Remote Client、VM、Terminal 實際操作、權限撤銷、timeout 故障注入、sleep/wake、24 小時 CPU/RSS/latency soak 尚未執行。
- Alt+Tab、Finder cut/move、非 US/ABC layout、中文 IME 翻譯、Home/End 尚未實作。
- UI 上看得到 Command+Q／關閉視窗的選單程式碼與選單列；未把快捷鍵操作列為已驗證結果。
- 未 notarize、未做 universal binary、未驗證其他 macOS 版本。

Command Line Tools 會輸出其不存在的 Developer framework search-path 警告，但此環境的 build/test 均成功。測試腳本載入隨工具鏈附帶的 Testing macro plugin；建置／簽章成品置於本機快取，避免 Documents 同步屬性干擾簽章。

這份紀錄區分單元／程序內 AppKit／打包啟動證據，不代表整個 MVP 或遠端相容性已驗收。
# 0.4.0-preview.1 HID 整合包（2026-09-27）

- 主程式 77 tests、helper 11 tests 通過；HID engine 120,000 events、codec 100,000 reports 均是離線測試。
- release App/helper build、strict codesign、兩個 CLI self-check 通過。controller CDHash pin 產生並與 ZIP 解壓後重算結果一致；沒有連接 Driver。
- installer shell syntax、plist、git diff whitespace 及 payload SHA256 驗證通過；在 /private/var/tmp 解壓再驗證兩個 App 簽章與 manifest。
- ZIP SHA256：`a19ee4d63a96c26f200be420a990aa7b5bacc57896187c8c202230acc29796bc`。
- 打包移到 Cache，避免同步資料夾重新加上 FinderInfo；installer snapshot 不複製 FinderInfo/resource fork。
- 未執行管理員 installer、root XPC runtime 驗收、seize、Driver activation、真實 report delivery、TCC 撤權／硬體斷線／睡眠、Remote Client 或長期資源量測。App/helper ad-hoc 未公證；正式替代 gate 見 HIDIntegration。
- Hosted CI 狀態以此 tag 所指 commit 的 Actions 為準，不以先前 0.3 的通過結果代替。

# 0.4.1-preview.1 設定與圖示包（2026-09-28）

- 主程式 82 tests、helper 11 tests 通過。新安裝啟用 EventTap／所有鍵盤、Codex macOS override 與底層 ABC／U.S. 的 IME 快捷鍵；Terminal／其他 IDE／Remote／VM 保持保護。舊設定及手動移除 Codex override 保留；損壞或未知 schema 安全停用且不覆寫原資料。
- release App/helper、CLI self-check、strict codesign、plist、shell syntax 與 git diff whitespace 通過。解壓 ZIP 的 payload SHA256、controller pin、版本、ICNS／兩個 Menu Bar template 圖示及 UserGuide 檔案皆驗證通過。
- ZIP SHA256：`4b3d2cec978f3594a5ad9dba8ae86504f2678a3ed0b50492eea2869c8b51961e`；大小 5,024,406 bytes。
- macOS 27.0 GUI smoke：四個分頁可開啟、一般／App 規則排版已檢視，套用建議預設後 IME 開關 ON、Codex 為 Default macOS。新簽章 App 尚未重新取得 TCC，Event Tap Inactive、事件計數 0；不是實體 Ctrl+C／V 驗收。
- 關閉設定視窗後可見視窗數為 0；20.01 秒短期量測 CPU 約單核心 0.1%，RSS 162,784 → 149,552 KiB。當時未授權、tap inactive、唯音守護停用；此數據不能代表啟用後的長期 CPU、實體記憶體 footprint 或鍵盤延遲。
- 未安裝或啟用 root helper／Driver，也未進行 HID 擷取、遠端 Client、中文組字／候選或硬體實測。App/helper 仍為 ad-hoc、未公證。HID 與完整替代驗收限制沿用前節。

# 0.4.1-preview.2 精簡 Menu Bar 圖示（2026-09-28）

- Menu Bar 有效／暫停圖示從 28×18 點改為 16×16 點的方形鍵位／雙向箭頭；App 圖示與快捷鍵規則未改。兩張 template PNG 是 32×32 pixel，對應 2x 顯示。App/helper build number 改為 6。
- 本機 `bash scripts/test.sh`、helper 的 11 項測試、release App/helper 建置與 self-check 均通過；ZIP 解壓完整性、內部 payload manifest 與 strict codesign 均通過。120,000 HID 事件與 100,000 report 編碼屬離線壓力測試，沒有接管實體鍵盤。
- 舊版 preview.1 在此機已重新取得 Accessibility／event posting／listening；診斷顯示 EventTap Active、Secure Input OFF。設定視窗關閉後，25.05 秒穩態 CPU time 差換算為單核心 0.08%，RSS 89.4 → 77.6 MiB，量測後 physical footprint 65.3 MB。另一次包含關窗後活動的 25 秒為 1.20% 單核心、RSS 97.2–97.8 MiB。這些是短期閒置量測，並非高頻輸入或長期記憶體證明。
- 介面自動化在 TextEdit 送出 Ctrl+A 沒有增加 EventTap 計數；此輸入沒有走實體攔截路徑，不能當成 Ctrl+A 功能驗收。實體鍵盤、Codex 複製貼上、Terminal／Remote Client 穿透、中文組字／候選、Finder 與睡眠喚醒仍需逐項驗收。debug 診斷已關閉並清除。
