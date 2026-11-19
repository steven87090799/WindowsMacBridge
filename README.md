# WindowsMacBridge

WindowsMacBridge 是給 **Apple M 系列 Mac**（macOS 14 以上）的選單列工具。它把 Windows 習慣的 Ctrl、Win、Alt 快捷鍵轉成 macOS 操作，並提供 Finder 操作、截圖複製、MacBook 內建 Fn／左 Ctrl 交換及選配的唯音／ABC 管理。也可在接收端 Mac 處理已辨識的遠端輸入。

WindowsMacBridge brings Windows-style shortcuts, Finder actions and screenshot copying to Apple silicon Macs. Start with the release download or the build guide. The Intel porting guide is for readers who want to adapt their own fork to x86_64.

| 我要做什麼 | 從這裡開始 |
| --- | --- |
| 下載與安裝 | [目前正式發行版](https://github.com/steven87090799/WindowsMacBridge/releases/latest)、[build 69 預覽版](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.3-preview.69)、[操作指南](Resources/UserGuide.md) |
| 在 M 系列 Mac 從原始碼建置 | [Build 與封裝](Docs/Build.md) |
| 自行做 Intel 版 | [Intel x86_64 移植步驟](Docs/IntelPorting.md) |
| 了解程式、測試或提交修改 | [架構與原始碼索引](Docs/Architecture.md)、[貢獻指南](CONTRIBUTING.md)、[給程式助理的注意事項](AGENTS.md) |

## 版本與相容性

| 版本 | 可取得的內容 |
| --- | --- |
| **v1.0.3（build 69）** | [最新正式版的 Apple M 系列 ZIP／DMG、更新說明與待驗收項目](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.3)。包含 Ctrl 多選、Finder 文字導覽、瀏覽器快捷鍵和遠端通道修正。 |
| **v1.0.3 預覽（build 69）** | [原預覽發行](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.3-preview.69)，與 v1.0.3 正式版使用相同的安裝檔。 |
| **v1.0.2（build 66）** | [上一個正式版的 arm64 ZIP／DMG](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.2)。含背景當機修正與有界自動復原。[發行說明](Docs/ReleaseNotes-1.0.2.md) |
| **v1.0.3 上一版預覽（build 68）** | [預覽發行的 arm64 ZIP／DMG](https://github.com/steven87090799/WindowsMacBridge/releases/tag/v1.0.3-shortcuts.20261103)。新增 Ctrl 點選與拖曳、Finder／瀏覽器快捷鍵和遠端相容規則。 |
| **`main`** | 最新開發原始碼，見 [Build 指南](Docs/Build.md)。build 69 各輸入路徑的實機驗收狀態列於[審查紀錄](Docs/WindowsProductionReview-2026-11-05.md)。 |

發行包供 Apple Silicon（`arm64`）使用。Intel 讀者可在自己的環境依指南移植。App 的執行版本下限是 macOS 14，建置工具的系統需求另見 Build 指南。Liquid Glass 界面在支援該 API 的 SDK 與 macOS 26 以上使用，較舊系統有毛玻璃介面。

## 安裝與第一次使用

1. 下載相符版本的 DMG，開啟後把 WindowsMacBridge 拖到「應用程式」。更新前先從選單列正常結束舊版。
2. 從「應用程式」開啟 App，保留預設的「一般模式」。在權限頁依序核准**輔助使用**與**輸入監控**。回到 App 確認狀態，依提示重開 App。需要截圖時另核准**螢幕錄製**。
3. 在 TextEdit 測試 Ctrl+C／V。需要調整時，從選單列開啟設定或「規則預覽」。可隨時從選單列暫停、恢復或結束。登入時啟動可自行開啟。

現有發行包使用 ad hoc 簽章，尚未經 Apple 公證。確認下載頁及 SHA-256 後，若 macOS 阻擋開啟，可依系統提供的「仍要打開」流程處理。更新可能要求重新核准當前 App。安裝一般模式不需要 Homebrew、Xcode、管理員密碼或額外 Driver。見[最新版安裝說明](https://github.com/steven87090799/WindowsMacBridge/releases/latest)。

## 一般模式與進階 HID

| | 一般模式（預設） | 進階 HID（選用） |
| --- | --- | --- |
| 鍵盤 | 使用者層 EventTap，涵蓋本機鍵盤，沒有可靠的逐裝置識別 | 可依裝置選擇實體鍵盤及鍵位偏好 |
| 權限 | 輔助使用、輸入監控。截圖另需螢幕錄製 | 同左，另須安裝背景服務和核准官方 Karabiner Driver |
| 啟用 | 由 Windows 模式總開關控制 | 先解鎖進階選項，選 HID 後明確安裝 |

切回一般模式前，App 會確認舊 HID 已釋放鍵盤。若畫面顯示尚未確認，放開按鍵並確認鍵盤正常，再選「恢復／重啟引擎」。移除 WindowsMacBridge 的背景服務會保留共用 Driver。完整流程見[單一 App 安裝說明](Resources/Installer/READ-ME-FIRST.md)與 [HID 後端](Tools/HIDBackend/README.md)。

## 快捷鍵與功能

以下以 `main` 的行為為準。各發行版的變更見[發行說明](https://github.com/steven87090799/WindowsMacBridge/releases)和下載包隨附的指南。

| 功能 | 使用方式 |
| --- | --- |
| 複製、貼上與常用快捷鍵 | Ctrl+C／X／V／A、儲存、復原、文字導覽、分頁。Terminal 的 **Ctrl+C 一律複製，Ctrl+Shift+C 中斷命令**。 |
| Win 與 Alt | Mac 的 **Option ⌥ 對應 Win，Command ⌘ 對應 Alt**。Option+E 開 Finder、Option+L 鎖定，Command+Tab 切 App、Command+F4 關目前視窗。外接鍵盤以實際送入的修飾鍵為準。 |
| Finder | Ctrl+X 再 Ctrl+V 移動、F2 改名、Delete 移到垃圾桶。Shift+Delete 經 Finder 確認。本機檔案焦點無法確認時，剪下移動規則不猜測要移哪個項目。 |
| 滑鼠（build 68 起） | Ctrl＋左鍵多選。Finder Ctrl＋拖曳複製、Ctrl＋Shift＋拖曳建立替身。 |
| 截圖 | Shift+Option+S、PrintScreen 或啟用時的 ⌘⇧3／4。完成後直接複製 PNG，點縮圖開啟 App 內的圖片預覽。Option+PrintScreen 另存到桌面；⌘⇧5 可使用系統標記與分享。OCR 目前停用。 |
| MacBook 鍵盤 | Fn／左 Ctrl 交換預設關閉。啟用只影響該台 MacBook 的內建鍵盤，外接鍵盤與另一台 Mac 各自維持原設定。 |
| 輸入法 | 唯音／ABC 切換和守護都是選用功能，各自預設關閉。 |
| 設定與診斷 | Windows 模式總開關控制快捷鍵、Fn／Ctrl、Finder 和截圖。規則預覽使用合成輸入。遠端校準需確認來源及結果後才套用。 |

詳細按鍵與前景 App 差異見[操作指南](Resources/UserGuide.md)、[Windows 鍵位對應](Docs/WindowsKeyMapping-2026-10-28.md)。預設規則與自訂 App 綁定衝突時，先檢查「規則預覽」和目的 App 的選單。

## 遠端與實機驗收

- **Windows → Google 遠端桌面 → Mac**。由接收的 Mac 執行 Bridge。已辨識來源的原始 Ctrl 可翻譯，已轉成 Command 的組合保持原樣。可在接收端校準來源。尚未辨識的第一個事件可能原樣通過。
- **Apple 螢幕共享**。各 Mac 分別安裝、授權與設定。Bridge 驗證接收端的 Apple 螢幕共享代理程式身分。兩個方向分開測試，各用對應的實體 Ctrl 或已設定的 Fn。
- **通用控制**。分別記錄來源鍵盤、操作實際落在哪台 Mac，以及重連結果。
- **Mac → 遠端 Windows 或 VM**。原始 Windows 按鍵交給目的系統處理。避免把遠端客戶端的 App Profile 改成本機 App 規則。

原始碼測試、下載包驗證、系統權限與實體輸入各有獨立的驗收結果。兩台 Mac 間能傳送剪貼簿內容，只證明剪貼簿同步。見[功能驗收](Resources/AcceptanceGuide.md)、[雙機驗收](Resources/TwoMacAcceptance.md)、[Apple 螢幕共享紀錄](Docs/ScreenSharingVNC-2026-10-24.md)。

## 開發與回報

```sh
bash scripts/build-app.sh             # arm64 App，輸出路徑在 build/APP_PATH.txt
bash scripts/test.sh                  # Swift 測試及獨立記憶體回歸
```

Git clone 和 GitHub 無 `.git` ZIP 都可建置。首次建置下載並驗證固定版本的 SDK。完整 ZIP／DMG、工具鏈與檢查步驟見 [Build 指南](Docs/Build.md)。歷史版本與修正可從 [Releases](https://github.com/steven87090799/WindowsMacBridge/releases) 查閱；有問題可用 [Issues](https://github.com/steven87090799/WindowsMacBridge/issues) 回報。

本倉庫目前沒有專案層級的授權檔。第三方組件各有自己的授權，見 [Resources/Licenses](Resources/Licenses)。對外分發專案衍生版本前，請先與權利人確認授權。
