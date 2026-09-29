# WindowsMacBridge HID helper

0.4 整合測試版：已接入 App 的 NSXPC、IOHIDDevice 擷取與官方 VirtualHID 輸出。仍待實機驗收；未在開發期間安裝 root 服務、啟動 Driver 或擷取任何實體鍵盤。

```sh
bash scripts/build-hid-helper.sh
bash scripts/build-app.sh
bash scripts/package-hid-release.sh
```

SDK revision `ba98de7fae2d529b9debe82890765dc66246f4ff`，archive SHA256 `a682e6a6afa1f06014e8065bde1adf42da1f1eaf81cc9a95943a2337581f667f`；官方 package 8.6.0，Driver 10800、client protocol 7。SDK archive 保持原狀，`prepare-hid-sdk.py` 另複製 headers 加入 service output-completion signal，供 wrapper 的 256 筆 outstanding 上限與 500 ms 無回應保護使用。這代表 service 回應，不代表目的 App 已收到按鍵。

C ABI 在 `Sources/VirtualHID`；root daemon 入口與裝置 adapter 在 `Sources/BridgeHIDHelper`；純生命周期模型在 `Sources/HIDLifecycle`；核心轉譯與 USB/Carbon 鍵位表共用主專案 `BridgeCore`；控制／status／固定 action ID 共用 `HIDProtocol`。

`--self-check` 僅測 report codec；`--controller-pin AppPath` 僅驗證靜態簽章及輸出 CDHash pin，均不連 Driver／不擷取。`--serve` 僅供安裝完成後的 root launchd 使用，要求 root-owned pin；`--probe-driver` 會建立暫時虛擬鍵盤，未在這次開發驗證中執行。

安裝／移除、授權、Terminal／Remote 策略、Caps Lock／Fn／layout 限制與硬體驗收：[HIDIntegration](../../Docs/HIDIntegration.md)、[READ-ME-FIRST](../../Resources/Installer/READ-ME-FIRST.md)。
