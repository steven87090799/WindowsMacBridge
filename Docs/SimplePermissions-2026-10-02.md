# 簡化安裝與權限（0.5.17 / build 35）

此版依使用者最新要求取代 build 34 的一鍵安裝 UI：第一次開啟完整單一 App 時自動準備安裝；安裝完成後直接顯示八项權限。取消或失敗不自動反覆開啟安裝。沒有一鍵安裝／修復按鈕、加入背景程式按鈕或資料夾選取流程。正常使用只需逐項點「開啟設定」、在 macOS 核准、返回看綠燈。其他設定放在進階頁面。

第 6 項自動啟動已安裝 helper 的短暫權限申請模式，由登入使用者的 Cocoa session 呼叫 IOHIDRequestAccess，再開啟輸入監控設定。這個模式不建立 DeviceCapture、不連 Driver、不接管鍵盤，也不替代 root daemon 的現有連線；提出要求後退出，沒有常駐輪詢。root daemon 只回報 IOHIDCheckAccess 的實際結果。這參考 [Karabiner 的官方架構說明](https://karabiner-elements.pqrs.org/docs/help/advanced-topics/security/)，權限要求應在使用者登入 session 執行。是否實際取得仍以 native check 判斷，沒有自行核准 TCC。

第 8 項自動對 macOS 目前的截圖儲存資料夾進行有上限的原生讀取，讓系統提出所需的檔案與檔案夾申請。使用者不選路徑；只去該列的系統設定核准。沒有受 TCC 保護、原本即可讀取的位置，實際讀取通過即可綠燈。

另發現 build 34 內含的 7.3.0 rollback pkg 權限為 600，安裝後 root 所有權導致一般使用者無法讀取；因此安裝後 deep codesign 檢查及再次複製內含安裝檔會遇到 Permission denied。修正僅將安裝的 App／helper 公開程式資源設為可讀／可執行、不可供非 root 修改，沒有變更使用者資料、TCC、Driver 或其他 App 的權限。以 production 安裝交易的私人目錄測試重現 private source mode，確認安裝結果可讀且不可由 group／other 寫入。

Windows 截圖與取消生命週期修復承接 build 34，詳見 OneClickSetupRepair-2026-10-02.md。只進行必要的 Release 建置、針對性安裝回歸及封裝檢查。權限核准、實體 Windows 快捷鍵、兩台 UC、Driver 重開機與記憶體峰值仍由實機驗收，不能把程式檢查通過當成完成。

2026-10-02 晚上 22:04 已從 preview.7 單一 App 啟動自動安裝流程，完成後自動開啟 `/Applications/WindowsMacBridge.app`；主 App 與 helper 皆為 build 35。安裝後 App 的 deep/strict codesign 與 helper 的 strict codesign 通過，內含 rollback pkg 為 root:wheel、644，先前的一般使用者讀取問題已排除。實際 GUI 預設顯示八項權限及每列「開啟設定」，沒有安裝／修復、加入程式或選取資料夾按鈕。

此時第 4 項登入啟動、第 5 項 Finder 擴充為已核准；第 1、2、3、6 項尚未取得，第 7 項仍為 `activated waiting for user`，第 8 項尚未檢查。沒有代替使用者核准。安裝包為 `build/download/WindowsMacBridge-0.5.17-preview.7-app-macos-arm64.zip`。

## Build 36 分頁調整

依使用者後續更正，保留 build 35 的八項權限清單與核准流程，恢復原本上方分頁：權限、一般設定、唯音與輸入法、App 規則、診斷。移除獨立「進階設定」、返回權限按鈕與對應狀態；每次只掛載目前分頁，沒有新增計時器或背景工作。只進行必要 Release 建置及封裝檢查，沒有重跑功能測試。新版安裝包為 `build/download/WindowsMacBridge-0.5.17-preview.8-app-macos-arm64.zip`。

2026-10-02 晚上 22:12 已完成 build 36 安裝；GUI 確認上方五個分頁直接可見，預設為權限頁，八項清單與各列「開啟設定」均保留，沒有獨立進階設定。App/helper 均為 build 36，安裝後簽章檢查通過。未代替使用者核准系統權限。

## PR 編譯相容性修復

PR CI 的較舊 Swift／CoreGraphics SDK 發現本機新版工具鏈未報告的相容性問題：PDF dictionary/object 在舊 SDK 同為 opaque pointer alias，不能依型別多載；改為明確命名兩種巡覽函式。截圖 observer 不再依賴 isolated deinit，改由可轉移 handle 在主 queue 釋放 FSEvents，stream context 保留弱 owner，避免背景 final release 後的晚到回呼讀取已釋放物件。未加入常駐工作或輪詢。新增背景釋放回歸，僅執行 NativeScreenshotObserverTests 三項，均通過；PR 完整檢查另以 Hosted CI 結果為準。此來源相容性修復未重新安裝或替換既有 preview.8 本機產物。

CI 當機堆疊另確認 helper permission probe 的 XPC error handler 被舊 SDK 的非 Sendable closure 推斷為 MainActor；XPC 背景回呼在執行 Task hop 前已觸發 actor 檢查中斷。XPC 回呼現在明確標為 Sendable，再回主 actor 處理；連線以 UUID 辨識，舊回呼不能作用於新連線，停止回覆仍須符合自己的 stop UUID。新增不存在的 helper service 回歸，BackendOwnershipTests 五項針對性檢查通過，涵蓋失聯、獨立權限查詢、停止回覆及釋放 controller。CI 保留失敗時的當機診斷輸出。
