# Build 60：Windows 複製貼上可靠性審查

Ctrl+C／X／V／A 使用共用的本機剪貼簿政策。本機 Game／停用延伸規則 Profile、Terminal、ABC／注音及已辨識遠端來源均適用；Windows viewer／VM 收到原始 Ctrl，由 Windows 執行對應命令。Terminal 的 Ctrl+C 固定複製，Ctrl+Shift+C 中斷命令。

## 找到並修正的失效路徑

- 原生截圖與 Quick Look 等浮動視窗的 target PID 可以不同於前景 App。輸入 callback 使用實際接收程序；程序尚未進入 NSWorkspace 快照時，立即給予基本剪貼簿規則，隨後由主執行緒補齊身分。未知視窗不取得底下 Finder 的移動／刪除等操作。
- Finder 與 Terminal 的 Ctrl+C 曾走有期限的非同步操作，可能被焦點切換、忙碌或取消淘汰。現在複製直接轉換原生 Command 鍵盤事件，Terminal 不再查詢 AX 選取狀態。Finder 沒有剪下標記時的 Ctrl+V 也直接轉換。
- 僅改變 flags 可能留下來源的控制文字；直接設定 Unicode 又會使 AppKit 將事件視為文字輸入而拒絕選單快捷鍵。現在重建原生 keyboard event，保留 target PID、時間戳、keyboard type、repeat 與 Caps Lock，讓 AppKit 依當前輸入法處理 Command 等效鍵。事件交給 Quartz 釋放，不保留每次按鍵物件。
- 先前不支援的文字輸入來源與本機穿透 Profile 會擋掉基本剪貼簿。現在只有延伸導覽規則受這些選項限制；總開關、暫停與安全狀態仍控制整個引擎。
- 接收視窗切換時重複清除來源狀態，會遺失仍按住的 Ctrl。現在保留連續的實體修飾鍵歷史，先結束舊按鍵輸出，再讓新按鍵使用新視窗；暫停、權限、session、後端／原生擷取所有權中斷會保留失效紀錄，不因快速切回而恢復舊狀態。
- 動作 mailbox 的 try-lock 曾連帶使整個鍵盤 processor 失效。基本複製不再依賴 mailbox；被拒絕的 Finder 剪貼簿動作退回原生剪貼簿按鍵，仍保留成對的 down／repeat／up。此時不推測檔案移動。
- Finder 的檔案剪下／貼上使用獨立有界佇列，避免等候系統 App 啟動。普通複製在 callback 立即撤銷較舊的剪下 ticket；較舊的完成不能清除較新的 ticket。過期但仍在相同有效視窗中的貼上會退回普通貼上，不能延遲移動檔案。
- HID 後端對本機 Profile 與輸入法保留基本剪貼簿規則；跨 App／layout 保留 Ctrl 需有相同 host modifier epoch。可選 epoch 欄位與舊 host 相容，缺少證據時仍採原有保守交接；Windows guest 的原生所有權交接不使用連續性。

## 驗證

`bash scripts/test.sh` 共 518 項通過：42 + 2 + 15 + 40 + 236 + 182 + 1。最後一項截圖記憶體回歸獨立程序執行。完整輸出位於 `/tmp/wmb-clipboard-audit-full-final.log`。

回歸涵蓋左右 Ctrl、先放修飾鍵／先放字母、repeat、輸入法與 Profile 組合、實際 AppKit 選單的 C／X／V／A、原生事件接收資訊、尚未收到啟動通知的視窗、持 Ctrl 進出浮動視窗、HID 與遠端來源交接、佇列拒絕／逾時，以及檔案剪下遭較新複製取消。Finder 測試只使用獨立 pasteboard、注入的 emitter 與產生的 file URL；不操作使用者檔案。

最終 NSImageView 預覽的 UI 檢查確認：點縮圖一次後取得焦點，Ctrl+C 複製產生的完整 1200×700 PNG，Esc 關閉。這個 fixture 不啟動輸入引擎、不擷取畫面或申請權限。多螢幕置中的座標計算有離線測試。

原生截圖編輯器的實體鍵盤操作、實際 HID Driver、不同遠端連線與多螢幕／全螢幕仍需安裝候選版本後驗收；離線測試與自製預覽不能取代這些驗收。App 被暫停、尚未授權、macOS Secure Input 或未辨識／沒有本機接收證據的事件，不會繞過系統保護。目標 App 也必須提供可用的複製／貼上命令。

## OCR 與交付

`ProductFeatures.screenshotTextRecognition` 固定為 `false`；設定頁與選單無 OCR 入口，封裝不含 OCR worker。辨識原始碼與 opt-in 測試保留，一般截圖只處理圖片。

本次修正為 build 60 候選版本。審查過程未替換 `/Applications/WindowsMacBridge.app`，目前安裝版本仍為 build 58；也未更改 TCC、系統快捷鍵、Root helper 或 Driver。
