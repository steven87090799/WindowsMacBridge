> 2026-10-28：目前統一 Option＝Win、Command＝Alt，Shift+Option+S 框選截圖。下方 Win＝Command 屬歷史紀錄，見[現行按鍵對應](WindowsKeyMapping-2026-10-28.md)。

# Fn／Ctrl 與通用控制複製診斷（2026-10-23）

狀態：已安裝 build 62，完成本次故障路徑與內建 Fn／Ctrl 的實體驗收，以及關閉／退出的映射還原檢查。下文分別列出使用者實測、事件 metadata 與自動測試，未用屬性讀回代替實體驗證。

## 版本與環境

- 檢查起點為 `/Applications/WindowsMacBridge.app`，0.6.0 build 60，Info.plist 的 `WMBGitRevision` 為 `fca84086ca08bc9b6f657581844b8909cfb85d1c`，`WMBSourceState=clean`。
- 與 tag `v0.6.0-preview.8`、`origin/codex/screenshot-focus-system-shortcuts` 的 commit 相符。修復分支 `codex/fix-macbook-fn-control` 從此 commit 建立；未以 main 推論版本行為。
- MacBookPro18,3，arm64，macOS 27.0.1（26A434）。GUI 權限頁實際顯示輔助功能／輸入監控已取得；從 shell 執行的權限診斷回報不同，不能取代 GUI 的權限結果。
- Windows 模式開啟，eventTap 後端，Fn／Ctrl 交換開啟，Windows 鍵位置為 Command。OCR 保持停用，原始碼保留。

## 實際觀察

| 項目 | 證據 |
|---|---|
| 內建實體裝置 | `AppleHIDTransportHIDDevice`，Registry ID `0x100000aa4`（4294970020），VID 1452／PID 834，SPI，Built-In=true |
| 原生鍵盤服務 | `AppleHIDKeyboardEventDriverV2`，Registry ID `0x100000aab`（4294970027），Generic Desktop／Keyboard（1／6） |
| Fn usage | 服務的 IORegistry 屬性 `FnModifierUsagePage=255`、`FnModifierUsage=3`；SupportedKeyboardUsagePairs 亦含 `0xff00000003` |
| 原映射 | 僅原生內建服務有 `ff:3 → 7:e0`、`ff01:3 → 7:e0`、`7:e0 → ff:3`；ModifierMappingPairs 為空 |
| Karabiner | 核心服務與虛擬鍵盤存在；選取 profile 的複合規則已停用，但 core_service.log 記錄上述實體裝置為 grabbed，之後沒有停止記錄 |
| 通用控制 | 有 `V-USB Receiver`、`V-MX Keys Mini` 鍵盤服務；它們不是本機內建映射目標 |
| 使用者後續釐清 | 兩台 Mac 都執行 WindowsMacBridge。MacBook 內建鍵盤經 UC 控制另一台 Mac，Fn+C 正常；另一台 Mac 的外接鍵盤經 UC 控制本 MacBook，Ctrl+C 失效 |

早期曾回報「沒有開控制中心」、「自己貼上可以了」，之後又回報失效／再次成功。由於使用者後續釐清了不同鍵盤與 UC 方向，這些早期回報不能全部當作本機內建 Fn+C 驗收。工具對剪貼簿的快照也沒有確認純測試字串，因此不視為獨立複製成功證據。

## 已執行的本機修正

先備份 `~/.config/karabiner/karabiner.json` 為 `karabiner.before-wmb-fn-fix-20261023-160607.json`，只在選取 profile 新增 VID 1452／PID 834／is_keyboard=true／is_pointing_device=false 的 `ignore=true` 裝置設定。JSON 比對確認只有此 profile 的 devices 欄位改變。16:06:07（台北時間）Karabiner 日誌記錄該裝置的 hid queue value monitor stopped。

這是內建鍵盤被 Karabiner 接管的實際證據。由實體裝置轉送到虛擬鍵盤、繞過原生服務映射，是符合架構與症狀的因果解釋；尚無逐事件追蹤證明每次失敗都走此路徑。UC 反方向 Ctrl+C 則已依下一節的實際事件定位。

## 通用控制複製失敗的直接證據與程式根因

build 61 權限由使用者重新核准後，GUI 確認已取得權限且 Event Tap Active。開啟 5 分鐘診斷，使用者以另一台 Mac 的外接鍵盤透過 UC 在本 MacBook TextEdit 按兩次 Ctrl+C，兩次均失敗並有操作失敗提示音。

診斷記錄顯示兩次連續 `flagsChanged(key=59, Control=true)` 後才是 `keyDown(key=8, Control=true)`；兩個 Ctrl down 之間，`synchronized` 由 true 變成 false。`enabled=true`、`neutralWait=false`，實際收件 PID 是 TextEdit；不是權限、收件 App、或等待放鍵阻擋。事件為 PID=0／state=1，走 physicalFallback，沒有經已辨識 UC PID 的 aggregate 修復路徑。完整關鍵節錄見 [UCControlEventEvidence-2026-10-23.txt](UCControlEventEvidence-2026-10-23.txt)。

`InputEngine` 原以 `aggregateDown && !previousSideDown` 推算這一側是否按住，將 flagsChanged 當成切換事件。第二次相同 down 被錯判為 release，而事件 aggregate 仍有 Control，故 ModifierStateMachine 失去同步；KeyboardEventProcessor 隨後拒絕翻譯剪貼簿快捷鍵，將 Ctrl+C 原樣送給 TextEdit。

修正後採 IOKit `IOLLEvent.h` 的左右 device mask 判斷各側狀態，能辨識另一側仍按住時本側放開。缺少 device bits 的傳輸則保留 aggregate 的按住狀態，直到實際的中立邊緣，不因重複事件憑空產生 release。本次沒有把所有 keyDown 的 aggregate flags 都當成可同步證據，原有遺失修飾鍵邊緣的保護仍保留。

新增的回歸測試用實際重複 down 順序，在有 side bits／只有 aggregate flags 兩種情境測 C／X／V／A；舊算法測試失敗（16 個 assertion issues），修正後通過。另測左右 Ctrl 重疊放鍵，以及八個原生修飾鍵側別對 SDK constants 的對應。

未清除全部鍵盤映射、未重設 TCC、未安裝 Root helper 或 Driver。建置腳本下載既定 SDK 到使用者 cache 作為編譯依賴，未註冊或安裝服務。

## 程式修改

- Mapper 的 `activeDevices` 改為 `mappedDevices`，明確只代表映射表一致；顯示「已寫入映射；實體按鍵尚待確認」。
- 偵測到 Karabiner 虛擬鍵盤時顯示條件式輸入路徑提醒；不將「存在」當成「正在接管」的證據，不修改共用虛擬鍵盤。
- `--diagnose-backend` 列出 Registry ID、class、Fn usage、內建／映射目標及兩種映射表，明示不代表實體驗證。
- 5 分鐘記憶體診斷增加 Ctrl／Fn 邊緣與 C／X／V／A 快捷鍵的 metadata，包含來源、實際收件 PID、flags、等待放鍵與處理結果。上限仍為 128 筆，關閉清除，不讀輸入文字或剪貼簿。
- 第一個診斷版標為 0.6.0 build 61；包含修飾鍵修復的版本為 build 62，來源均為指定 commit 上的修改。

## 已完成驗證

- 原生映射開啟／關閉 A/B：關閉後只有 `0x100000aab` 改為空映射，其餘服務全部一致；journal 已清除。
- build 60 正常退出：所有服務映射與上述關閉快照完全相同，journal 已清除；重啟後內建映射恢復。
- Fn／Ctrl 針對性測試 29 項通過。
- 狀態／metadata 修改後的完整自動測試 520 項通過（42 + 2 + 15 + 40 + 238 + 182 + 1）。後續短期事件診斷修改另行測試，不能沿用前次結果當作實體證明。
- 短期事件診斷與 mapper 的 25 項針對性測試通過；release App 建置、簽章檢查與自我檢查通過。GUI 未載入 OCR framework，套件內沒有 OCR worker。
- build 61 已替換 `/Applications/WindowsMacBridge.app`。原 App 另存於上述 evidence 目錄的 `WindowsMacBridge-deployed-build60.app`。重新編譯的 ad-hoc designated requirement 從 build 60 的 cdhash `cbad36dbcf9e32abbedc6a6e209932cfea8b386d` 變為 `8a9fbf01fce46d6c5767810949720c198d61fd05`；GUI 顯示原鍵盤權限未取得，已請求使用者同意重新啟用這兩項既有權限。尚未重設 TCC，也未代為核准。
- 使用者隨後自行重新授權，build 61 GUI 三項權限已取得、Event Tap Active；已完成上述失敗事件擷取。
- build 62 的完整自動測試 **524 項通過**（42 + 2 + 15 + 40 + 242 + 182 + 1），包括重複 Ctrl down、左右 Ctrl 重疊放鍵、SDK 八側 device bits，以及原有未同步／遺失邊緣／生命週期保護測試。
- build 62 安裝後 GUI 原生確認權限已取得、Event Tap Active。使用者按相同路徑（另一台 Mac 外接鍵盤 → UC → 本 MacBook TextEdit），回報兩次複製貼上都成功；實際事件記錄同時確認重複 Ctrl down 的 synchronized 持續為 true，C／V 分別命中 `windows.copy`／`windows.paste`，原生 raw flags 為 `0x40101`（含 Left Control bit）。
- 使用者再直接用本 MacBook 內建鍵盤在本機 TextEdit 實測 Fn+A → Fn+X → Fn+V → Fn+C 並貼上，及原本左 Ctrl+C 的 Fn／控制中心行為，回覆「全部符合預期」。同時看到 `windows.selectAll`／`windows.cut`／`windows.paste`／`windows.copy` 命中，以及 key=63、Fn flag=16、rawFlags=0x800100 的事件。CGEvent 本身不提供可靠實體裝置 ID；鍵盤來源依此輪明確的使用者操作確認。
- build 62 關閉交換後只有內建服務 `0x100000aab` 的映射變為空，其餘當時服務的映射完全一致，journal 移除。再開啟後正常退出，所有映射與關閉快照一致、journal 移除、主程序已停止。
- 重新啟動 build 62 後，GUI 權限已取得並顯示「運作中」，內建服務交換表恢復。持續存在的其他服務映射不變；部分 UC 虛擬服務在此期間移除／重建並改用新 Registry ID，新服務映射皆空，已在 validation JSON 分別記錄，沒有將服務重建誤記成映射修改。
- 短期診斷已關閉並清除；進階模式恢復原本關閉。`bridge.settings.v1` 與最初備份逐欄比對完全相同，Windows 鍵位置仍為 Command。保留的環境修正為上述 Karabiner 內建裝置 ignore=true。

驗收範圍：本次確認的是本機內建交換、另一台 Mac 外接鍵盤經 UC 到本機的複製／貼上、映射還原及重新啟動。使用者先前也確認過 MacBook Fn+C 經 UC 到另一台 Mac 正常；本次沒有把該較早結果當成所有遠端軟體、所有裝置或所有跨機組合的驗收。

原始 metadata、映射快照、設定差異及 build 60 App 備份保存在 `/Users/steven/Library/Caches/WindowsMacBridge/Diagnostics/FnControl-20261023/`。
最終機器可讀驗證紀錄為該目錄的 `validation-build62.json`；保留 build 60／61 App 供需要時回復。原始碼、此報告與 [AI 交接筆記](Build62-FnControl-UniversalControl-Handoff.md) 隨修復分支與 `v0.6.0-preview.9` 發佈；發佈包從乾淨的提交重新建置，與早期 fca8408 modified 的本機試用包分開。

## 映射與快捷鍵順序的依據

[Apple TN2450](https://developer.apple.com/library/archive/technotes/tn2450/) 說明服務的 UserKeyMapping API。[Apple IOHIDKeyboardFilter 原始碼](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDEventSystemPlugIns/IOHIDKeyboardFilter.mm) 的 remapKey 先套修飾鍵表，再套 UserKeyMapping；部分已標記事件會略過 remap。這支持檢查映射所在服務與輸入路徑，不能把該公開原始碼當成 macOS 27 本次每個事件的追蹤結果。

本程式 InputEngine 的 tap 位於 annotated session。若 Fn+C 已被上游解讀成系統快捷鍵，不能假設在這個階段補改 flags 就能避免控制中心；本次不以盲目擴大 session tap 或對所有鍵盤交換作為修正。
