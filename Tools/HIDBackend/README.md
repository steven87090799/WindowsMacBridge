# WindowsMacBridge 選配 HID 後端

同一份 WindowsMacBridge App 包含一般模式的介面與 `--hid-service` 背景模式。預設一般模式使用 EventTap。只有在 App 裡解鎖進階選項、選 HID 並安裝後，才啟動 HID 服務、核准 Driver 並擷取指定鍵盤。

## 建置與檢查

從倉庫根目錄執行：

```sh
bash scripts/build-app.sh
bash scripts/package-single-app.sh
bash scripts/package-app-dmg.sh
```

操作詳見 [Build 指南](../../Docs/Build.md)。建置會準備固定版本的 SDK，完整封裝才附帶安裝材料。三個步驟皆不安裝 Driver、啟動服務或擷取鍵盤。選配 HID 的實際安裝與移除由 App 的進階設定提供。見[單一 App 安裝說明](../../Resources/Installer/READ-ME-FIRST.md)。

`--hid-self-check` 在 App 執行檔中檢查 report codec，`--controller-pin AppPath` 讀取靜態簽章身分，兩者都不連接 Driver。`--hid-service` 是已安裝的 root launchd 入口，要求 root 擁有的 App 副本及 pin。`--probe-driver` 會建立暫時虛擬鍵盤，僅用於有意驗證 Driver 的測試機。

## 程式與依賴

- [VirtualHID](Sources/VirtualHID) 提供 C ABI，[HIDRuntime](Sources/HIDRuntime) 實作裝置擷取與 XPC，[HIDLifecycle](Sources/HIDLifecycle) 定義停止／釋放行為。
- [BridgeCore](../../Sources/BridgeCore) 共用鍵位及翻譯規則，[HIDProtocol](../../Sources/HIDProtocol) 共用設定、狀態和固定動作。
- SDK revision 為 `ba98de7fae2d529b9debe82890765dc66246f4ff`。建置檢查 archive SHA-256 `a682e6a6afa1f06014e8065bde1adf42da1f1eaf81cc9a95943a2337581f667f`。完整安裝包使用簽署的 Karabiner 8.6.0 及 7.3.0 回滾套件。
- [prepare-hid-sdk.py](../../scripts/prepare-hid-sdk.py) 在獨立的 header 副本加入輸出回覆信號。包內官方 Driver 的名稱、二進位與簽章保持原樣。服務回報成功與目的 App 接到按鍵分開驗證。

停止、遠端交接和實體驗收仍需依[操作驗收](../../Resources/AcceptanceGuide.md)檢查。歷史設計見 [HID 整合紀錄](../../Docs/HIDIntegration.md)。
