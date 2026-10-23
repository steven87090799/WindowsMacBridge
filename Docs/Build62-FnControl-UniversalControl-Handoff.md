# Build 62：Fn／Ctrl、通用控制複製與封裝交接筆記

這份筆記提供下一位 AI／維護者直接接手。修復分支為 `codex/fix-macbook-fn-control`，發佈 tag 為 `v0.6.0-preview.9`，App 版本為 0.6.0 build 62。請以 tag／commit 確認原始碼；不要用較舊 main 判斷本版行為。

## 先讀結論

本次遇到兩個需要分開處理的問題：原生 Fn／Ctrl 映射的屬性成功提示不能證明實體生效；以及通用控制收到重複 Ctrl 狀態事件時，InputEngine 錯誤切換左右鍵歷史，造成 Ctrl+C／X／V／A 被原樣放行。

build 62 已在這次 MacBook 上完成使用者實體操作驗收：本機內建 Fn+C／X／V／A、原左 Ctrl→Fn，以及另一台 Mac 的外接鍵盤透過通用控制送入的 Ctrl+C／V。524 項自動測試通過，關閉／正常退出後的映射還原與重新啟動檢查也通過。這不代表所有 Mac、所有通用控制組合或進階 HID Driver 都已實測。

## 版本與最初症狀

起點是安裝中的 0.6.0 build 60，`WMBGitRevision=fca84086ca08bc9b6f657581844b8909cfb85d1c`，對應 `v0.6.0-preview.8` 與 `codex/screenshot-focus-system-shortcuts`。Windows 模式開啟、Windows 鍵位置 Command、Fn／Ctrl 交換開啟，介面顯示「已交換 Fn ↔ 左 Ctrl（1 個內建鍵盤）」，但原 Fn+C 開啟控制中心。

後續必須明確辨別操作來源。使用者釐清：

| 來源 → 目的端 | 按鍵 | 修復前觀察 |
|---|---|---|
| MacBook 內建鍵盤 → 通用控制 → 另一台 Mac | 原 Fn+C | 使用者回報正常 |
| 另一台 Mac 外接鍵盤 → 通用控制 → 本 MacBook TextEdit | Ctrl+C | 兩次均失敗，伴隨操作失敗聲音 |

兩台都有 WindowsMacBridge。不能把早期「貼上成功」一概當成本機內建鍵盤驗收，更不能把單向成功推論成雙向正常。

## 問題一：映射讀回與實際輸入路徑不同

這台 MacBook 的內建實體裝置為 SPI、VID 1452／PID 834；原生鍵盤服務是 `AppleHIDKeyboardEventDriverV2`。IORegistry 回報的 Fn usage 為 `0x00ff:0x0003`，符合原本的 `0xff00000003`。交換表確實寫在內建服務，並能讀回。沒有證據支持本次應改 Fn usage 常數。

同時 Karabiner 核心日誌明確顯示內建實體裝置已被 grabbed。即使複合規則停用，Devices 的 Modify events 仍會接管裝置；原生服務上的 UserKeyMapping 因此可能不是實際事件經過的位置。

本機先備份 Karabiner 設定，只對該內建裝置加入 `ignore=true`，日誌確認 monitor stopped；外接裝置設定保持原樣。這是環境修正，不是 App 對 Karabiner 的依賴，也沒有把個人 Karabiner 設定封裝進安裝包。新電腦沒有 Karabiner 就不需要安裝它；已有接管衝突時需在該機放行內建鍵盤。

程式修改：

- [MacBookKeyboardMapper.swift](../Sources/BridgePlatform/MacBookKeyboardMapper.swift)：`activeDevices` 改為 `mappedDevices`，顯示「已寫入映射；實體按鍵尚待確認」，保留 journal 的精確配對還原機制。
- [NativeMacBookKeyboardBackend.swift](../Sources/BridgePlatform/NativeMacBookKeyboardBackend.swift)：`--diagnose-backend` 增加 Registry ID、class、Fn usage、兩種映射與映射目標 metadata。詳細 IORegistry 查詢只在診斷命令執行。
- [SettingsView.swift](../Sources/WindowsMacBridge/SettingsView.swift)：顯示 Karabiner 虛擬鍵盤的條件式路徑提醒。「存在虛擬鍵盤」本身不當成「正在接管」的證據。

不能將屬性 setter／readback、虛擬鍵盤存在、或自動測試通過當成實體 Fn 成功。也不能把交換套到共用虛擬鍵盤，否則會波及外接／通用控制鍵盤。

## 問題二：重複 flagsChanged 被誤當成切換

build 61 是收集 metadata 的診斷版；build 62 才包含這項修復。使用者以確定失敗的路徑重現，收到以下順序：

```text
flagsChanged key=59 Control=true  synchronized=true -> true
flagsChanged key=59 Control=true  synchronized=true -> false
keyDown      key=8  Control=true  synchronized=false result=pass
```

`enabled=true`、`neutralWait=false`、收件 PID 對應 TextEdit，所以這次不是權限未取得、等待放鍵或收件 App 判錯。事件是 PID=0／state=1，分類為 `physicalFallback`；通用控制不是每次都以 `com.apple.universalcontrol` 的 PID 進入，不能只修改已辨識 UC PID 的分支。

舊程式在 [InputEngine.swift](../Sources/BridgePlatform/InputEngine.swift) 用：

```swift
aggregateDown && !previousSideDown
```

推算本側是否按住。第一次 Ctrl down 後歷史已為 down；第二次相同通知被推算成 false，等同虛構一次 release，卻仍有 aggregate Control。ModifierStateMachine 因此失去同步；KeyboardEventProcessor 正確拒絕在未同步狀態翻譯，Ctrl+C 原樣到 TextEdit，產生失敗聲音。根因在上游的狀態解碼，不應直接移除處理器的同步保護。

修正新增 `InputEngine.modifierDown`：

1. 使用 IOKit `IOLLEvent.h` 的左右 device mask 讀實際狀態，重複 down 保持 down。
2. 有 side bits 時，可辨別左右 Ctrl 同時按住、只放開其中一邊。
3. 只有 aggregate flags 時，保留回報的 held group，直到中立邊緣，不從重複事件憑空推算 release。沒有 side bits 時，不能宣稱可精確辨別 peer 仍按住期間的每一側 release。
4. 沒有把所有一般 keyDown 的 aggregate flags 都視為可信同步證據，原本的缺失邊緣／pause／session／recipient 安全機制保留。

修復後同路徑仍有重複 Ctrl 事件，但持續 `synchronized=true`；raw flags 為 `0x40101`，含 Left Control bit。C／V 分別命中 `windows.copy`／`windows.paste`，使用者實際貼上確認兩次均成功。

關鍵前後事件見 [UCControlEventEvidence-2026-10-23.txt](UCControlEventEvidence-2026-10-23.txt)；完整診斷與時間順序見 [FnControlDiagnosis-2026-10-23.md](FnControlDiagnosis-2026-10-23.md)。

## 測試與已驗收界線

- [ModifierInputTests.swift](../Tests/BridgePlatformTests/ModifierInputTests.swift)：使用實際重複 down 順序測 C／X／V／A，有 side bits／僅 aggregate 兩種；舊算法失敗（16 個 assertion issues），新算法通過。另測左右 Ctrl 重疊放鍵及八側 SDK mask。
- [ShortcutInputTraceTests.swift](../Tests/BridgePlatformTests/ShortcutInputTraceTests.swift)：短期診斷限於 Ctrl／Fn 邊緣和剪貼簿組合，不收一般文字與 repeat。
- [MacBookKeyboardMapperTests.swift](../Tests/BridgePlatformTests/MacBookKeyboardMapperTests.swift)：只驗證 property、衝突／外接隔離、精確還原、journal 與 metadata，不冒稱實體成功。
- `bash scripts/test.sh`：524 項通過，包括獨立程序的記憶體回歸。
- 使用者直接拿本 MacBook 內建鍵盤，在本機 TextEdit 測 Fn+A → Fn+X → Fn+V → Fn+C 並貼上，以及原左 Ctrl+C 的 Fn／控制中心行為，回覆「全部符合預期」。事件同時看到四個剪貼簿規則與 key=63／Fn flags。
- build 62 關閉交換、正常退出後，內建服務映射還原且 journal 移除；其餘當時服務映射一致。重啟後交換恢復、權限與運作中狀態正常。
- UC 虛擬服務可能移除／重建並改變 Registry ID。比對持續存在的服務與新服務的空映射，不把 Registry ID 更換誤判成被本 App 改了映射。
- 測試結束已關閉／清除 5 分鐘診斷、恢復一般模式與原設定；OCR 維持停用、保留原始碼。

CGEvent 沒有可靠逐實體裝置 ID，實測的鍵盤來源依使用者受控操作確認。未驗收的其他 Mac／OS／遠端軟體與進階 HID 安裝，不得從以上結果推論全部正常。

## 換機與 Release 封裝

正式提供的 ZIP／DMG 必須從乾淨的發佈 commit 重新建置，讓 `WMBGitRevision` 對應 tag，不能上傳仍標示 fca8408 modified 的早期本機試用包冒稱乾淨發佈。

```sh
bash scripts/build-app.sh
BRIDGE_RELEASE_VERSION=0.6.0-preview.9 bash scripts/package-single-app.sh
BRIDGE_RELEASE_VERSION=0.6.0-preview.9 bash scripts/package-app-dmg.sh
```

`build-app.sh` 產生的一般 App 沒有 BackendPayload；`package-single-app.sh` 才封入選用進階 HID 安裝／移除材料與官方 VirtualHID Driver 安裝包。一般模式不需要它們，打包也不等於在本機安裝 Driver。Driver 是官方 Karabiner DriverKit VirtualHIDDevice，不是自己的 Driver；本次沒有安裝 Root helper、重設 TCC 或清除全部映射。

完整發佈包只依賴 macOS 系統動態函式庫，不需要 Xcode、Homebrew 或本機 SDK cache 才能執行。此包是 arm64／macOS 14+，不是 Intel／Universal 版本；最低部署目標不是每個舊系統都已實機驗收的證明。

每台 Mac 仍要自行核准輔助功能、輸入監控、需要時的螢幕錄製；MacBook 的 Fn／Ctrl 開關新安裝預設關。通用控制需由 macOS 設定完成。不要複製舊電腦的還原 journal。App 為 ad-hoc 簽章、未 Apple 公證，更新簽章後可能要重新核准；GUI 原生確認是依據，shell 啟動的 TCC 診斷可能反映終端機身份。

換機步驟見 [InstallOnAnotherMac-build62.md](InstallOnAnotherMac-build62.md)。後續若要真正免初次開啟阻礙的正式對外發佈，需有效 Developer ID 與 Apple 公證；不要以關閉系統保護或放寬事件同步規則來迴避。
