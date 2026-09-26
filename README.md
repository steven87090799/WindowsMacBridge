# WindowsMacBridge

macOS Menu Bar 工具的第一個可編譯開發版本。Swift 6、macOS 14+、完全 User Space。

## 建置與執行

需要 Swift 6 工具鏈（Xcode 或 Command Line Tools）。沒有第三方套件。

腳本使用 `~/Library/Caches/WindowsMacBridge/` 作建置暫存與 `.app` 輸出，避免同步資料夾的 FinderInfo 屬性破壞簽章。實際 App 路徑寫入 `build/APP_PATH.txt`；可用 `BRIDGE_BUILD_DIR` 覆寫。測試腳本也會自動解析此 CLT 的 Swift Testing macro plugin；不修改 SDK。

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open "$(cat build/APP_PATH.txt)"
```

Xcode 使用 **File → Open → Package.swift** 開啟。這一版以 Swift Package + App 打包腳本提供，尚未建立獨立 `.xcodeproj`。

App 初次啟動預設停用。先按「要求 Accessibility」，在 **系統設定 → 隱私權與安全性 → 輔助使用** 授權這個 `.app`，再啟用 Windows 快捷鍵。Input Monitoring 有獨立的診斷與按鈕；不自動反覆要求權限。若引擎出錯，可從 Menu Bar 重新啟動或結束。

本地腳本預設 ad-hoc 簽署；更換路徑／重新建置可能需要重新授權。正式發行需固定 bundle ID、Developer ID 簽署與 notarization；目前不是已公證安裝包。不建議用 `swift run` 作權限驗收，因為 executable 身分不同。

## 已實作

- Menu Bar、SwiftUI 權限／App 規則／診斷頁面。
- Ctrl+C/X/V/A/Z/S/F/P → Command+相同鍵，Ctrl+Y → Command+Shift+Z。
- 精確 modifier 匹配：不接管 Ctrl+Option、Ctrl+Command 或原生 Command 組合。
- 獨立 input thread、CGEventTap、128 鍵 press ledger、左右 modifier 狀態、來源 marker。
- Terminal／Remote／VM／IDE／部分 launcher 內建通行規則；可自訂 App profile。
- Pause 5／15／60 分鐘、至重啟、Control+Option+Command+P 緊急暫停。
- timeout 有界恢復／熔斷、Secure Input、sleep/session suspension、權限狀態。
- 5 分鐘、最多 128 筆的記憶體規則診斷，關閉即清除；不記錄普通打字。

## 刻意保留的限制

- **僅 ABC／U.S. input source 啟用翻譯**。中文 IME 與其他 layout 原样通過，尚未完成非美式鍵位與 composition 相容性。
- **Alt+Tab 尚未接入**：不持有或注入 synthetic modifier，先避免跨 App 卡鍵風險。
- **Finder Ctrl+X 原樣通過**，沒有假裝檔案 Cut。Ctrl+C/V 使用正常 Finder Copy/Paste。
- Finder move、Home/End、Windows Key、window switcher、自訂快捷鍵編輯器都未實作。
- IDE 預設整個 App 通行，不猜 integrated terminal；手動選 Default macOS 會覆寫此保護。
- Remote Profile 只表示不改鍵，不能保證遠端收到按鍵、Ctrl+Alt+Delete 或 clipboard sync。
- Registry 中 Windows App、Parsec、Parallels 的 bundle ID 已對照此機安裝檔；其他項目為待驗證候選，不代表相容性認證。未知遠端／遊戲／helper 請加入明確 Profile。
- NSWorkspace 通知不是與按鍵原子同步；快速 focus race、raw HID 與第三方 remapper 仍需實機測試。
- 跨 App 時，舊翻譯的 repeat/up 被抑制；不向新 App 重播舊動作。舊 App 的 release 語意需實機測試。
- Ctrl+Y 的 keycode 改寫與其餘快捷鍵已通過 AppKit 選單的程序內測試；仍需以實際 event tap／目標 App 驗證。
- 緊急鍵使用同一 event tap；tap 失效／Secure Input／Client grab 時需用 Menu Bar 或系統強制結束。

## 隱私與驗證

不讀取 Unicode 輸入、不查 Clipboard、不保存 keyDown 序列、不網路上傳、不使用 private API。不需要 Full Disk Access／Screen Recording／root。

打包腳本會自動以 `--self-check` 驗證包內 Registry；這個模式不啟動 Event Tap。

單元測試包含 120,000 事件配對壓測；這只驗證 deterministic core，不是 CPU、RSS、端到端延遲或遠端相容性的證明。手動驗收詳見 [Docs/ReleaseAcceptance.md](Docs/ReleaseAcceptance.md)。
