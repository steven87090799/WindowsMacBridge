# Intel Mac 移植指南（x86_64）

這份指南供讀者在自己的 fork 或分支上建立 Intel 版。WindowsMacBridge 的主要建置、GitHub Actions 與 Releases 以 Apple M 系列（`arm64`）為準。以下是依現行腳本核對的轉換步驟，Intel 產物與實機相容性由移植者驗證。

## 1. 準備 Intel 建置機

在 Intel Mac 的原生終端機執行，`uname -m` 與 `xcrun swift -version` 的 target 應顯示 `x86_64`。建議從含 Swift 6.2.3、macOS 26.2 SDK 的 Xcode 26.3 開始，並準備 Git、Python 3 與下載固定版本 SDK 所需的網路。該 Xcode 需 macOS Sequoia 15.6 或相容的 Tahoe 版本，請參考 [Apple 工具鏈需求](https://developer.apple.com/xcode/system-requirements/)。App 的 deployment target 維持 macOS 14.0，舊系統能否執行請另做實機驗收。

```sh
git clone https://github.com/steven87090799/WindowsMacBridge.git
cd WindowsMacBridge
git switch -c port/intel-x86_64
uname -m
xcrun swift -version
xcrun --sdk macosx --show-sdk-version
python3 --version
```

Apple Silicon 上的 Rosetta 與交叉編譯各有工具鏈限制。建置腳本需要執行剛建好的 App 和 helper 做自檢，請以 Intel 機器或 Intel GitHub runner 作為本指南的建置環境。

## 2. 在移植分支調整原生編譯目標和封裝

| 檔案 | 在 Intel 分支的調整 |
| --- | --- |
| [`scripts/build-app.sh`](../scripts/build-app.sh) | 把 `WindowsMacBridgeRecovery` 的 `clang -target arm64-apple-macos14.0` 和 FinderSync 的 `swiftc ... -target arm64-apple-macos14.0` 分別改為 `-target x86_64-apple-macos14.0`。`swift build` 在 Intel 工具鏈會建出原生 Swift App 及其依賴，含 HIDRuntime。若啟用 OCR，SwiftPM 產出的 worker 也要驗證為 x86_64。保留 SDK、macOS 14.0 和原本的連結與簽章設定。 |
| [`scripts/package-single-app.sh`](../scripts/package-single-app.sh) | 把 `DriverProcessRunner` 的 `clang -target` 改為 `x86_64-apple-macos14.0`，ZIP 後綴改為 `-app-macos-x86_64.zip`。先核對 `build/APP_PATH.txt` 所指的 App 是本次 Intel 產物。 |
| [`scripts/package-app-dmg.sh`](../scripts/package-app-dmg.sh) | 把輸出後綴改為 `-macos-x86_64.dmg`。仍由 `build/SINGLE_APP_PATH.txt` 取得含進階材料的 App。 |
| [`.github/workflows/macos.yml`](../.github/workflows/macos.yml) | 若要在自己的 fork 做 Intel CI，另加使用 `macos-15-intel` 的工作並選擇相容 Xcode。把這份工作的 ZIP 解壓路徑、產物名稱和 build info 的 `architecture` 改成 `x86_64`，並以 `lipo` 實查，避免只換檔名。原有 arm64 工作可獨立保留。[GitHub runner 規格](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for-public-repositories) |

原生 Intel 建置可以沿用 SwiftPM 的主機預設架構。若移植者明確指定 SwiftPM 架構，必須在 App、選用 worker 和 `--show-bin-path` 呼叫使用同一架構與 SDK，避免取到舊產物。遷移所需變更集中在建置與封裝。快捷鍵、遠端來源辨識和 HID 規則使用同一份程式碼。

完整封裝內含原廠 Karabiner 8.6.0 與 7.3.0 回滾套件。查核時兩份固定套件的 manager、daemon 和 DriverKit 執行檔均內含 `x86_64` 與 `arm64`。保留官方套件原檔及既有 SHA-256、簽章驗證和 Driver 核准程序。套件具有 Intel 執行檔是編譯與封裝條件，實際安裝、核准及裝置擷取要另外驗收。

## 3. 建置並檢查產物

改完上述腳本後，在分支根目錄執行下列指令。若重做封裝，換一個 `BRIDGE_RELEASE_VERSION`，保留原有成品。

```sh
bash scripts/build-app.sh
export BRIDGE_RELEASE_VERSION=1.0.3-intel.1
bash scripts/package-single-app.sh
bash scripts/package-app-dmg.sh

app="$(cat build/SINGLE_APP_PATH.txt)"
lipo -archs "$app/Contents/MacOS/WindowsMacBridge"
lipo -archs "$app/Contents/Helpers/WindowsMacBridgeRecovery"
lipo -archs "$app/Contents/PlugIns/WindowsMacBridgeFinderSync.appex/Contents/MacOS/WindowsMacBridgeFinderSync"
lipo -archs "$app/Contents/Resources/BackendPayload/DriverProcessRunner"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/WindowsMacBridge" --self-check
"$app/Contents/MacOS/WindowsMacBridge" --hid-self-check
"$app/Contents/Helpers/WindowsMacBridgeRecovery" --self-check
(cd build/download && shasum -a 256 -c *-1.0.3-intel.1-*.sha256)
hdiutil verify build/download/WindowsMacBridge-1.0.3-intel.1-macos-x86_64.dmg
```

上述自行編譯的執行檔都應回報 `x86_64`。如果包內有 `Contents/Helpers/WindowsMacBridgeTextWorker`，也檢查它。把 ZIP 解壓至非同步暫存資料夾，再對解出的 App 檢查架構與簽章。檢查 App、FinderSync、Recovery 的 `vtool -show-build` 應記錄所選 SDK 與 `minos 14.0`。封裝後請核對 `Info.plist` 的版本、build、`WMBGitRevision` 和 `WMBSourceState`。

## 4. 驗證與交付

1. 跑 [Build 指南的 Swift 與 Python 測試](Build.md#驗證改動)。Intel 的 SwiftPM 測試宿主如果沒有簽章，`ControllerRequirementTests` 無法取得自己的 CDHash。先確認錯誤來源，可在 Intel 測試的 linker 參數加 `-Xlinker -adhoc_codesign`，重跑原本的 XPC 身分驗證案例。保留匹配與拒絕的兩個測試。
2. 在 Intel Mac 實測一般模式的輔助功能、輸入監控、左右 Ctrl、Finder 與截圖。若要交付進階 HID、Fn／Ctrl 或遠端功能，再按[功能驗收](../Resources/AcceptanceGuide.md)及[雙機驗收](../Resources/TwoMacAcceptance.md)驗證各路徑。離線驗證時避免安裝或啟動輸入後端。
3. 分享時列出所建提交、Intel 機型／系統、SDK、實測範圍及簽章狀態。以 manifest／SHA-256 對應各個 x86_64 檔案，讓讀者可以區分自己的產物與專案的 arm64 Releases。
