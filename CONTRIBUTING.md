# 貢獻與回報

WindowsMacBridge 以 macOS 上的 Apple M 系列為主要開發與發行平台。閱讀 [README](README.md) 確認發行版與 `main` 的差異，再依 [Build 指南](Docs/Build.md) 建置。架構、測試位置與輸入契約見[原始碼索引](Docs/Architecture.md)。使用 AI 協作時，先讓它讀取 [AGENTS.md](AGENTS.md) 及相關驗收紀錄。

## 回報問題

在 [GitHub Issues](https://github.com/steven87090799/WindowsMacBridge/issues) 附上：

- App 版本／build 或 commit、macOS 版本、Mac 晶片和鍵盤種類。
- 一般模式或進階 HID，以及必要權限是否在 App 內顯示已授權。
- 最短的重現步驟、預期行為與實際結果。遠端問題另外列出兩端系統、實體按鍵、接收 App、連線方向，以及重連後是否重現。
- 用可丟棄的 TextEdit 文字、檔案或圖片重現。移除真實鍵入文字、剪貼簿內容、個人路徑和權限資料後再貼記錄。

## 提交修正

1. 由 `main` 建一個分支，先確認問題出在哪條輸入或建置路徑。修改 Apple 螢幕共享／VNC 或 MacBook Fn 交換前，讀[代理人注意事項](AGENTS.md)與[雙機驗收](Resources/TwoMacAcceptance.md)。
2. 用 `bash scripts/test.sh` 驗證變更。輸入規則要核對一般模式、HID、規則預覽、遠端來源和放鍵配對。封裝改動另外驗證原始碼版本、架構、簽章、校驗值和 ZIP／DMG 內容。
3. 在 PR 說明觸發方式、修正結果和已執行的檢查。標明需要實機完成的部分，特別是權限、HID、Google 遠端桌面、雙向 Apple 螢幕共享和通用控制。歷史發行測試依其版本保留。

Intel 的移植者可依 [Intel 指南](Docs/IntelPorting.md)在自己的 fork 維護 x86_64 建置，不必把第二套建置或執行判斷加進 M 系列的主要流程。
