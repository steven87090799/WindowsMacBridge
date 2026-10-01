# WindowsMacBridge 0.5.14（build 26）修復候選版

Windows 快捷鍵與唯音／ABC 輸入法輔助整合在一個 macOS Menu Bar App。適用 Apple Silicon、macOS 14+。這次修復的根因、完整測試與未完成驗收見 [2026-09-30 修復報告](Docs/PreReleaseRepair-2026-09-30.md)。實體 HID、Universal Control、Remote、macOS 授權與安裝復原仍須驗收，**目前不宣稱可正式上線**。

## 使用與權限

一般 EventTap 模式將 App 放進 Applications 即可，不需 helper／Driver。新安裝開啟 Windows 快捷鍵、所有鍵盤、截圖自動複製與底層 ABC／U.S. 的中文快捷鍵；Finder 增強、亮度鍵開啟檔案、Alt+F4、永久刪除與 Win+R/I/Tab 預設關閉。既有設定保留。MacBook 預設交換本機內建 Fn／Ctrl，桌上型 Mac 預設關閉。

授權清單由目前 App 的原生 API 查驗。前往設定按鈕只開啟 macOS 設定；綠勾需系統確認權限。App/helper 使用 ad-hoc 簽章，沒有 Apple 公證；若系統阻擋，使用系統提供的「仍要打開」。不要關閉 Gatekeeper／SIP。完整操作、唯音守護、登入與移除方式見 [UserGuide](Resources/UserGuide.md)。

## 快捷鍵與後端

- Ctrl 快捷鍵、瀏覽器分頁與 Windows 文字導覽保留原有規則。Terminal／IDE 保護原生 Ctrl 語意，Remote／VM／Game 原樣通過。Codex 預設針對聊天文字；若使用內建 Terminal，改成 IDE 或移除該規則。
- 自製 Alt+Tab 已移除。Tab 不被翻譯成自製切換器；原生 `⌘Tab` 與 `⌘\`` 由 macOS 處理。HID 的 Option／Command 裝置配置仍依實體 Win 鍵設定套用。
- Finder Ctrl+X 以原生 Copy 建立 5 分鐘待移動狀態，開資料夾、上一層與切換路徑不取消；Ctrl+V 由 Finder 移動。剪貼簿改變、切 App、暫停或失效會取消。Delete 僅在確認檔案選取時轉為移到垃圾桶，文字／未知焦點保持前刪。永久刪除另有開關與逐次確認。
- Alt+F4 只使用 Accessibility 按目前視窗的關閉按鈕，保留 App 的未儲存提示。無可用關閉按鈕時回報，沒有 Command+W／Q fallback。
- HID 的亮度增加 consumer key 預設保持原樣。只有開啟獨立選項、Finder 增強已開且前景為本機 Finder，才轉成 Enter。
- EventTap 沒有可靠的公開來源 device ID。HID 模式只由 helper 處理接管裝置，不啟動盲目的第二套 EventTap 翻譯。所有支援的簡單 keyboard descriptor 可接管，另保留內建／Apple 834 範圍；複合或無法安全接管的裝置維持原生，仍有覆蓋限制。
- 後端交接等 helper 停止擷取回覆後才啟動新後端。逾時會保持新後端停用並顯示原因；放開所有按鍵再恢復。

## 截圖與遠端

兩個後端均支援 Win+Shift+S 框選、Alt+PrintScreen 目前視窗、Win+PrintScreen 全螢幕存檔，以及 PrintScreen。PrintScreen 可選框選或傳統全螢幕複製；完成後自動複製 PNG。EventTap 的 PrintScreen 使用鍵盤實際送出的 F13 位置，須實測鍵帽配置。

暫停、停用、後端／session／generation／Secure Input 改變立即取消舊工作；逾時、權限、程序、磁碟、解碼與編碼失敗各有狀態。單一 capture slot 在工作真正結束前不接受新工作。圖片先檢查檔案、像素、尺寸、解碼記憶體預算；PNG 沿用原始編碼，不同時生成 TIFF。已完成的存檔保留。系統 `⇧⌘4` 保持原樣。

「遠端輸入角色」提供本機自動、接收原始 Windows、接收原生 Mac、來源已有 Bridge，以及傳送／Universal Control 來源。這是手動指定輸入語意，不猜來源。兩端都裝 Bridge 時，先決定哪端翻譯，另一端選穿透。Client 全螢幕、剪貼簿與快捷鍵轉送仍由 Client 控制；瀏覽器遠端分頁可使用專用瀏覽器並指定 Remote App 規則。

## 可靠性與資源

統一 immutable runtime policy 綁定 backend、device scope、前景、remote role、pause、Secure Input、session、設定與 generation。輸入 callback 只處理有界 state／查表；AX、檔案、圖片、UI 與 native process 啟動在 callback 外。按鍵16裝置／256 press slots、動作16筆、log128筆／64 KiB，事件風暴只排一個 drain。保留 Secure Input、neutral recovery、session validation、heartbeat lease 與失聯釋放。

Fn／UserKeyMapping 在寫入前同步保存私人還原 journal；按鍵未放開時延後修改。正常關閉還原；force quit 後下次啟動恢復，不能宣稱 SIGKILL 後即時還原。更新 helper 使用 staging → verify → switch，正常失敗還原 App/helper/pin/服務狀態，SIGKILL 中止後下次執行安裝器先由私人 journal 復原；共用 Driver 版本不同時停止，舊 App 備份最多兩份。

## 建置與測試

需要 Swift 6 工具鏈。主 App 無第三方 Swift 套件；helper 使用固定 checksum 的官方 VirtualHID SDK。腳本從 Git clone 或沒有 `.git` 的 ZIP 均能建置；ZIP 記錄 `archive` source state，可用合法十六進位 `SOURCE_REVISION` 指定來源。建置輸出在 `~/Library/Caches/WindowsMacBridge`，指標在 `build/`。

```sh
bash scripts/test.sh
bash scripts/test.sh -c release
python3 -m unittest discover -s Tests/InstallerTests -v
python3 -m unittest discover -s Tests/MonitoringTests -v
bash scripts/build-app.sh
bash scripts/build-hid-helper.sh
bash scripts/package-app-dmg.sh
bash scripts/package-hid-release.sh
```

App 使用明確 resource bundle allowlist，Finder extension Release 預設 `-O`，可用 `FINDER_RELEASE_OPTIMIZATION=-Osize` 比較。helper build 與 self-check 不安裝或啟動 Driver。HID 安裝與授權見 [READ-ME-FIRST](Resources/Installer/READ-ME-FIRST.md)，架構見 [HIDIntegration](Docs/HIDIntegration.md)，實機步驟見 [AcceptanceGuide](Resources/AcceptanceGuide.md)。

鍵盤事件不網路上傳，不保存密碼／OTP／普通打字，不讀既有 Clipboard payload。Finder focus 使用有界 AX role/parent 與一筆 file URL metadata 確認選取，沒有保存 URL 歷史；路徑選單只有使用者點擊複製才寫 Clipboard。截圖僅處理這次新產生的圖片。保留 [VChewingGuard MIT](Resources/Licenses/VChewingGuard.txt)、官方 SDK／Driver 與 vendor 授權聲明。
