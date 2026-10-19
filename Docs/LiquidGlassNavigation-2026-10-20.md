# 設定導覽的流動玻璃與背景釋放（build 57）

## 需求與 API 研究

- 移除左上角顯示／隱藏側邊欄按鈕及自動焦點。一般表單的鍵盤操作保留；導覽按鈕關閉焦點光暈，Tab 只移動焦點，不更換頁面。
- Apple 的 [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) 說明 `GlassEffectContainer`、`glassEffectID` 和 `glassEffectTransition(.matchedGeometry)`：同一容器內的玻璃可在切換時移動、融合與形變，容器也能減少繪製成本。
- 本機 macOS 27.0 / SDK 27.0 / Swift 6.4 的公開 SwiftUICore interface 確認上述 API 與 `Glass.interactive()` 從 macOS 26 起可用。macOS 27 的系統實作會提供當前材質與使用者的玻璃外觀偏好，沒有把 iOS UIKit 放進 macOS App。
- [Modernize your AppKit app, WWDC26 14:09–15:25](https://developer.apple.com/videos/play/wwdc2026/289/) 說明 macOS 27 的玻璃與互動回彈改進。AppKit 的 `NSGlassEffectView.effectIsInteractive` 是另一套介面；本導覽直接使用 SwiftUI 的公開互動玻璃 API。
- Apple [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) 建議把玻璃用於導覽／控制層，避免玻璃疊玻璃。因此移除原本整片自製玻璃面板，只讓選取項目有一層原生玻璃；底層是標準系統背景色，不再多做整片 backdrop 繪製。

## 實作

`SettingsNavigation.swift` 將所有導覽列放進一個 `GlassEffectContainer`，只有目前選取的那一列建立玻璃。選取層共用一個 effect ID，以有限的彈簧動畫移動；容器的 340 pt proximity 涵蓋八個 40 pt 列與間距的最長跳躍。快速連續切換會重新導向目前動畫，而不排入計時器。

按鈕有選取的 accessibility trait、說明與上下方向鍵操作。沒有全域攔截 Tab、修改系統鍵盤導覽偏好或 TCC。`focusEffectDisabled` 限於導覽，不影響設定內容的文字欄位。

「減少動態效果」停用過渡動畫；「減少透明度」或「提高對比」改用實色選取。macOS 14/15 使用相容選取材質，不能提供 macOS 26/27 的折射。

設定視窗關閉、App 隱藏、視窗最小化時，移除 NSHostingController 與 contentView，釋放玻璃與 SwiftUI 觀察。解除隱藏、還原或重新開啟設定時才建立新視圖，保留現有視窗尺寸與 controller 中的設定／所選頁面。CPU／記憶體專頁依原本可見性規則取樣。

未加入 display link、輪詢、持續動畫、資源歷史或 GPU shader。釋放設定 UI 不等於整個 App 的記憶體為零：輸入引擎、選單列與系統框架快取仍有基本用量；保留一個最小化／隱藏的原生 NSWindow 也有少量成本。

## 驗證與範圍

開發模式只使用自產內容，不啟動 BridgeController、輸入服務、權限、截圖或剪貼簿。

- 20 張明暗／最小尺寸／高對比的離屏版面。
- 原有 11 個 CPU／記憶體專頁可見性轉換。
- 增加 10 次快速切換導覽（80 次選取）及 120 次原生 Tab 焦點遍歷，確認 Tab 不改頁。
- 增加 5 次保留 NSWindow 的視圖卸載／還原，核對卸載後的 hosting controller、hosting view、fixture state 已釋放，還原後視窗尺寸保留。
- 釋放後再量測 30 秒 CPU，並記錄 footprint 與全部弱參照的最終狀態。

測試的執行結果另存本次交付的驗證目錄。離屏版面可驗證排版，不能證明 WindowServer 的實際玻璃折射或可見 GPU 負載；實際切換手感、系統輔助使用設定、真實最小化／Cmd-H 與還原仍須實機驗收。沒有用使用者畫面或一般剪貼簿來驗收。

## CI 工具鏈

下載成品改由 GitHub 的 `xcode-27` 原生 arm64 runner、固定 `/Applications/Xcode_27.0.app` 製作，另外執行當代玻璃路徑的版面與釋放檢查。完整 Debug／Release、Installer、Monitoring 與相容 UI 閘門仍在 macOS 15 / Xcode 26.3 執行，避免只驗證新系統。

Runner 可用性與工具鏈路徑取自 [actions/runner-images 官方清單](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)；這個 runner 標籤目前仍標為 preview，執行狀態與產物必須以本次 commit 的 CI 為準。

主線第一次成品檢查發現，Swift 6.4 / Swift Build 即使在 SDK 27 下編譯，執行檔的 `LC_BUILD_VERSION.sdk` 仍可能被寫成最低部署版本 14.0；獨立的最小 Swift Package 也重現相同結果。建置腳本現以所選 SDK 的實際版本明確傳入 linker 的 `-platform_version macos 14.0 <sdk>`，保留 macOS 14 最低需求。打包前對主程式、OCR worker 與 Finder extension 逐一檢查連結 SDK 和最低部署版本，SDK 不符即停止，不能只因 Xcode 版本正確就發布。這會讓系統的 linked-on-or-after 外觀判斷取得正確來源；實際玻璃效果仍需可見視窗驗收。

離屏程序沒有進入 `NSApplication.run()`，因此所有 AppKit 關閉操作都放在局部 autorelease pool 內，模擬正常原生事件迴圈會排空的釋放範圍。開發時新增的卸載測試曾把關閉操作放在外層，造成 5 個原生視窗延後釋放的誤判；程序記憶體圖確認持有者是外層 autorelease pool，修正後獨立 5 次卸載／還原檢查的 35 個弱參照全部釋放。沒有為了通過測試移除檢查或改成只隱藏視圖。

## 本機結果

- Swift 回歸 492 項（含獨立記憶體檢查）通過。
- 20 張自產明暗、最小尺寸與高對比版面完成；工具列側邊欄按鈕已移除，說明入口移至側邊欄底部，使用標準置中的原生視窗標題。
- 完整資源檢查 306 個弱參照全釋放；80 次選取、120 次 Tab 遍歷、5 次卸載／還原與 11 種取樣可見性轉換通過。
- 卸載後 30.009 秒使用 0.000893 CPU 秒，約為單核心 0.0030%。此數字只代表自產離屏 UI 程序，沒有輸入引擎，也不是可見 GPU 量測。
- 該程序初始 footprint 約 7.3 MB、框架暖機後關閉約 31.5 MB、全部新情境執行並關閉後約 39.1 MB。弱參照歸零不代表框架快取或整個 App 占用歸零，這次短測也不足以判斷長時間成長。

本機原始證據：`~/Library/Caches/WindowsMacBridge/glass-navigation-20261020/`，包含失敗的測試、修正後報告、記憶體圖及引用追蹤。發布與安裝狀態另見該處 `delivery-state.json`；不以本機檢查代替精確 revision 的 hosted CI 與成品驗證。
