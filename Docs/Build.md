# 在 Apple Silicon Mac 建置 WindowsMacBridge

專案以 Apple M 系列晶片（`arm64`）為主要開發與發行平台。App 的最低執行版本是 macOS 14。執行 App 所需的系統版本和安裝 Xcode 所需的版本不同。

## 準備環境

- 使用 Apple Silicon Mac 的原生終端機。`uname -m` 應顯示 `arm64`。
- 準備 Git、Python 3，以及含 macOS SDK 的 Xcode 或相容的 Command Line Tools。現行 CI 使用 Xcode 26.3（Swift 6.2.3）及 Xcode 27（Swift 6.4）。請依 [Apple 的工具鏈需求](https://developer.apple.com/xcode/system-requirements/) 選擇可在建置機上安裝的版本。
- 第一次建置需連線下載固定版本的 Karabiner VirtualHID SDK。封裝完整安裝包時，還會下載固定版本的官方 Driver 回滾套件。腳本會驗證 SHA-256，建置時無需安裝 Driver 或授予輸入權限。

如果有多套 Xcode，可在目前終端分頁用 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 指定已安裝的版本。以下指令可確認目前使用的工具和 SDK。

```sh
uname -m
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
python3 --version
```

## 建立 App

```sh
git clone https://github.com/steven87090799/WindowsMacBridge.git
cd WindowsMacBridge
bash scripts/build-app.sh
```

也可以使用 GitHub 的 **Code → Download ZIP**。解壓後進入包含 `Package.swift` 的目錄，執行相同建置指令。沒有 `.git` 的來源會標為 `archive`。Git checkout 建出的 App 會記錄提交與工作樹狀態。

建好的 Release App 位於本機快取，完整路徑寫在 `build/APP_PATH.txt`。可用 `BRIDGE_BUILD_DIR` 指定本機非同步資料夾，以免檔案同步工具在 App 加入會影響簽章驗證的 Finder metadata。

```sh
app="$(cat build/APP_PATH.txt)"
lipo -archs "$app/Contents/MacOS/WindowsMacBridge"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/WindowsMacBridge" --self-check
```

應看到 `arm64`。這個 App 已可做離線檢查。要取得含進階 HID 安裝材料的 App，請繼續封裝。

## 封裝 ZIP 和 DMG

在同一份來源目錄，先完成上面的 App 建置，再執行：

```sh
export BRIDGE_RELEASE_VERSION=1.0.3-local.1
bash scripts/package-single-app.sh
bash scripts/package-app-dmg.sh
(cd build/download && shasum -a 256 -c *-1.0.3-local.1-*.sha256)
hdiutil verify build/download/WindowsMacBridge-1.0.3-local.1-macos-arm64.dmg
```

`BRIDGE_RELEASE_VERSION` 是產物檔名的版本標籤。重複封裝時換一個標籤，以保留既有檔案。`build/download/` 會有 `-app-macos-arm64.zip`、`-macos-arm64.dmg` 及各自的 `.sha256`。`build/SINGLE_APP_PATH.txt` 記錄含完整 HID 安裝材料的 App。倉庫預設使用 ad hoc 簽章，證明本機可驗證其完整性。GitHub 的既有發行包尚未經 Apple 公證。

## 驗證改動

| 要驗證的範圍 | 指令或步驟 |
| --- | --- |
| Swift Debug、Release 與獨立記憶體回歸 | `bash scripts/test.sh` 和 `bash scripts/test.sh -c release` |
| 安裝、回滾、背景復原、資源監測 | 分別執行 `python3 -m unittest discover -s Tests/InstallerTests`、`python3 -m unittest discover -s Tests/RecoveryTests`、`python3 -m unittest discover -s Tests/MonitoringTests` |
| 精確提交的建置、簽章與介面檢查 | [GitHub Actions](https://github.com/steven87090799/WindowsMacBridge/actions) 依[工作流程](../.github/workflows/macos.yml)執行並保存產物 |
| 鍵盤、系統權限、進階 HID 與遠端桌面 | 依[功能驗收](../Resources/AcceptanceGuide.md)及[雙機驗收](../Resources/TwoMacAcceptance.md)各自測試 |

請使用 `scripts/test.sh` 作為完整測試入口。它會先準備固定版本 SDK，並把程序記憶體回歸放在獨立程序執行。要在其他分支自行移植 Intel，請依 [Intel 移植指南](IntelPorting.md)調整建置和封裝。
