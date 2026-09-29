# macOS 27 設定視窗警告調查（2026-09-28）

環境：macOS 27.0（26A428）、arm64、Command Line Tools。這份結果只適用於本機重現，
不等於已在 macOS 14／15 或無螢幕擷取的工作階段驗證。

## CoreUI bundle 查找

原本 SwiftUI `TabView` 使用圖示標籤；換成純文字標籤仍重現 CoreUI bundle 警告。
改為 segmented Picker、只掛載一頁內容後，本機四頁反覆切換未再出現該類警告。
Picker 的頁面狀態改到下一個 main queue turn 發布，亦消除切頁中的
`Publishing changes from within view updates` 警告。未降低日誌層級或過濾錯誤。

## AppKit 負尺寸：已定位到系統視窗框架，未宣稱修復 macOS

使用 `log show` 取得僅屬本程式／獨立測試 App 的 fault stack，再以 `vmmap` 的
AppKit image base 加 imageOffset，透過 `atos -p` 符號化。只讀取診斷 metadata，
沒有修改系統 framework、注入 debugger、呼叫 private API 或讀取鍵盤內容。

正式設定視窗的 60 筆，以及獨立測試 App 的 48 筆 width／height fault，
frame 4 均為 AppKit imageOffset `10247368`：

```text
_NSViewValidateGeometry
NSViewValidateSize
-[NSView setFrameSize:]
-[NSThemeFrame _positionSharingIndicator] + 64
-[NSThemeFrame layout]
...
-[NSWindow layoutIfNeeded]
```

這條路徑屬於 macOS 的視窗分享指示器。獨立 App 沒有 EventTap、輸入法、
權限要求或 BridgeCore；原生視窗、普通文字、SwiftUI ScrollView、原生
NSScrollView（零／非零初始 frame、overlay／legacy scroller）都可在 UI 操作下重現。
因此將 grouped Form 換成自製卡片、調整 hosting view 的初始尺寸都未消除它。
最後保留原生 Form／List，避免沒有證據支持的複雜 workaround。

目前證據能定位此批 warning，不能證明所有 macOS 27 負尺寸警告都來自同一問題，
也不能證明離開自動化／分享情境後必然消失。App 不隱藏分享指示器、不使用私有
API 修補 NSThemeFrame；若後續出現不同 stack、裁切、無法操作或背景持續警告，
應另開問題，不能直接套用此結論。

## Safari 全螢幕回報

使用者回報 YouTube／Safari 綠色按鈕全螢幕失效並有提示音。初查 Safari 存在
「允許網站開啟 Codex」的待處理對話框；取消後繼續檢查，Safari 視窗可進入
全螢幕，選單顯示「離開全螢幕」，點選後正常返回視窗。當時候選版未重新取得
Accessibility，EventTap Inactive；此结果不能代表引擎啟用後的端到端驗收，
也不足以確定原先故障由該對話框造成。未自動允許網站權限。

靜態檢查：EventTap mask 只有 keyDown／keyUp／flagsChanged；不截取滑鼠。
規則以完整 modifier 集合精確匹配，沒有原生 Control+Command+F 或無修飾鍵
F／Escape 的翻譯。新增兩個回歸測試，在已同步的 modifier 狀態下確認原生
全螢幕／視窗快捷鍵保留，以及 Ctrl+C 完整放開後 F、Escape、K、Space、M、
方向鍵保留。這些程序內測試不等同實體鍵盤或 Safari 播放器驗收。
