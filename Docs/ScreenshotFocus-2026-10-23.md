# Build 59：截圖預覽焦點與系統浮動視窗快捷鍵

點擊自製截圖縮圖後，原本以 `Process` 執行 `qlmanage -p`，沒有將新程序啟用；可能只在 Dock 出現快速查看圖示，需要第二次點擊。現在使用 App 所有的 `NSWindow` 與 `NSImageView`／可縮放的 `NSScrollView`，在縮圖所在螢幕的可用範圍置中，明確啟用 App 並讓預覽成為 key window。仍只有點擊後才建立完整預覽；關閉、新截圖、暫停與退出會關閉預覽，再清理 App 所有的暫存圖片。明確保存的截圖不刪除。

預覽中的 Ctrl+C／Cmd+C 都會在背景讀取完整原圖，透過原有圖片預算與剪貼簿寫入流程複製；關閉或較新的複製要求會取消過期寫入。Esc／空白鍵可關閉預覽。沒有新增背景輪詢或常駐檢視程序。

原本 `InputEngine` 只接受 annotated target PID 等於前景 App PID 的新按鍵。原生截圖、Quick Look 等系統浮動視窗可能接收鍵盤焦點，同時保留底下 App 為 NSWorkspace 的 frontmostApplication。現在前景切換及程序啟動／結束時，主執行緒建立接收程序的 App 規則快照；輸入 callback 只依 WindowServer 的實際接收 PID 查詢快照，不呼叫 NSWorkspace／AX 或掃描程序。修飾鍵與新按鍵都選用接收程序規則，Ctrl+C／X／V／A、復原、儲存等一般 Windows 規則因而適用於系統浮動視窗。App 自己的視窗也使用一般 Windows 規則。

未知或缺少接收程序時仍不借用底下 App 的規則；Finder／Terminal 等依賴選取範圍的非同步操作仍須前景所有權。遠端 Windows／虛擬機使用原始 Ctrl 組合；Secure Input、暫停、權限撤銷及來源限制仍由既有政策處理。沒有更改系統快捷鍵設定或 TCC 資料。

## 驗證範圍

回歸涵蓋原生截圖視窗覆蓋 Finder／Terminal／遠端 App 時的規則選擇、未知接收程序、乾淨的遠端到本機視窗交接，以及不同螢幕座標、完整原圖複製與關閉釋放。預覽關閉會取消待處理的圖片解碼與複製。顯示圖片的長邊限制 4096 像素，完整原圖仍供複製使用。封裝檢查曾發現嵌入 Quick Look 會載入 Vision／CoreML，最終改成原生圖片視窗以維持 OCR 只在獨立程序按需載入。

完整 Debug 測試共 498 項通過，包含獨立程序執行的截圖記憶體回歸。Info.plist lint 與 diff 空白檢查通過。

`--screenshot-preview-fixture <新目錄>` 只產生測試圖片並顯示縮圖，不啟動輸入引擎、不拍攝畫面或要求權限；60 秒縮圖期限與 180 秒執行期限僅供明確啟動的測試模式使用。實際點擊測試確認一次點擊後預覽取得焦點，Ctrl+C 將 1200×700 完整測試圖寫入剪貼簿。這不代表原生截圖編輯器中的實體 Ctrl+C、多螢幕／全螢幕與跨 Mac 已完成實機驗收。

## OCR 產品開關

依使用者要求，目前產品視為沒有 OCR。`ProductFeatures.screenshotTextRecognition = false` 同時隱藏設定頁與選單入口、阻止預設 ScreenshotManager 啟動文字擷取，並使封裝腳本不建置、複製或簽署 OCR helper。App 自檢會拒絕帶有 OCR helper 的停用版封裝。原有辨識、獨立程序與測試程式碼保留；測試透過明確注入 opt-in 驗證保留的功能，不會啟用產品入口。一般截圖與圖片複製不依賴 OCR。
