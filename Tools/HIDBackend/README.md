# BridgeHIDHelper 開發原型

這是獨立建置的底層輸出原型，**尚未安裝或接入 Menu Bar App**。不提供 capture/serve 指令；不可當作完整 Karabiner 替代後端。

已實作：

- Swift helper → 穩定 C ABI → 官方 VirtualHID C++ client。
- Keyboard、Apple vendor top-case Fn、consumer brightness 三種 report 編碼；邊界檢查、duplicate rejection、32-key 上限。
- 僅 root 可建立 client；driver ready/version/fault gate，bounded 3 秒 probe，reset/close。`post` 成功只代表 enqueue，不是驅動確認。
- 相同輸出不重複 enqueue，重新連線後重建報告快取。
- 純生命週期模型：driver 未 ready / 按鍵未 neutral 不可 seize；未驗證控制器、1 秒 heartbeat 失效、Secure Input、撤權、sleep 產生 release-output 再 close-device；部分 open 失敗須明確 restart。
- 10 項離線測試，包括 100,000 次 report 編碼；沒有開 driver、抓鍵或送系統按鍵。

## 建置

在 repository 根目錄：

```sh
bash scripts/build-hid-helper.sh
"$(cat build/HID_HELPER_PATH.txt)" --self-check
```

首次下載約 107 MiB 的固定 SDK archive（上游 archive 也包含歷史 pkg，故體積較大）。檔案存於使用者 Cache；只編譯 header client，**不執行上游 installer 或 build script**。測試與建置不需 sudo。`--probe-driver` 只有 root 環境能執行，會暫時建立虛擬鍵盤並在結束時 reset，沒有實體 capture 或非空 report；本次沒有執行這條路徑。

- Upstream: [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ba98de7fae2d529b9debe82890765dc66246f4ff)
- Revision: `ba98de7fae2d529b9debe82890765dc66246f4ff`
- Archive SHA256: `a682e6a6afa1f06014e8065bde1adf42da1f1eaf81cc9a95943a2337581f667f`
- Package version 8.6.0 / driver 1.8.0 (`10800`) / client protocol 7。
- 本機 `pkgutil --check-signature` 確認 archive 內 8.6.0.pkg 為 Fumihiko Takayama 的 Developer ID Installer 簽署且 Apple notary trusted。只檢查 metadata，未安裝 pkg。

輸出 C ABI 位於 `Sources/VirtualHID/include/VirtualHID.h`；生命週期模型位於 `Sources/HIDLifecycle`。後者目前只供 adapter 契約測試，CLI 尚未執行任何 physical capture。

## 尚需完成

IOHIDDevice capture adapter、各 usage page 的完整 pass-through、device removal、repeat 與多鍵 output ownership、UI↔helper 的身分驗證 IPC、啟停/heartbeat 接線、Mac session/Secure Input 實際監控、受限 root installer/uninstaller、App backend selection、driver transport backpressure/ack，以及實機故障測試。

目前 client transport 採上游 async queue；尚未建立可證明 bounded 的 capture→driver pipeline，所以不能開始 seize。shutdown 的 100 ms reset window 亦不是交付保證；實際斷線與崩潰時的 release 須測試。不能把 lifecycle 純測試宣稱為已運作的 watchdog。

SDK 與相依 library 的著作權/授權留在原 archive；client headers 標示 Boost Software License 1.0，repository 頂層標示 Unlicense。將來發佈 helper binary 前，需隨安裝包保留實際連結元件的授權聲明；本次 App ZIP 沒有包含 helper binary、SDK 或官方 pkg。
