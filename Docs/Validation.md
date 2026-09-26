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
