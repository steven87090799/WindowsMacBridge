# WindowsMacBridge

Apple Silicon、macOS 14+ 的选单列键盘工具，整合 Windows 快捷键、MacBook 内建 Fn／Ctrl、Finder 操作、截图与选配唯音／ABC 管理。原始码版本 **0.6.0（build 43）双模式修复候选版**；[Releases](https://github.com/steven87090799/WindowsMacBridge/releases) 的已发布资产与原始码合并是不同阶段。

## 安装

点两下DMG，把WindowsMacBridge.app拖进Applications，正常退出旧版后替换。一般模式只引导辅助功能，回到App由AX／posting原生检查验证。没有自动Root安装、HID/XPC连接、Input Monitoring或Driver提示；登录启动需用户明确开启。截图第一次明确使用可能需要ScreenCapture授权。

App使用ad-hoc签章、尚无Apple公证；更新可能需要重新核准本版App，不能以同名旧授权项视为已通过。不要关闭SIP／Gatekeeper或重设其他App权限。

## 功能与默认

| 功能 | 一般模式默认 |
|---|---|
| Ctrl复制／贴上／复原／全选／储存、文字导览、浏览器分頁 | 开 |
| Alt+Tab、Alt+F4 | macOS原生切换／当前窗口关闭，保留未储存提示 |
| Finder Ctrl+X→V移动、F2、Delete、确认式ShiftDelete | 开；不需FinderSync，根目录监控已移除 |
| Windows截图与CmdShift3／4 | 开；完成直接写PNG clipboard，取消／旧session不写入 |
| MacBook Fn／左Ctrl | 关，明确开关只改本机builtIn键盘 |
| Windows键位置 | Command，可选Option |
| 唯音守护／Carbon切换热键 | 各自关，保留手动输入来源 |
| Terminal／IDE／Remote viewer／VM／Game | 依App profile保护Ctrl语意 |
| HID／VirtualHID／root runtime | 进阶选配，默认关 |

一般模式EventTap使用全部键盘，没有可靠逐装置ID。旧HID选择不自动解锁新进阶模式，已有App规则、键位与明确功能选择保留。Settings schema 6，损坏设置安全停用。

进阶抽屉勾选后才显示后端、安装／移除、Driver、装置偏好与诊断。所有材料封装在同一App；root模式用root-owned签章镜像，不让root执行用户可替换的Applications文件。共享官方Karabiner Driver不改签章名称、不因切一般或卸载本App的runtime被删除。支持的Driver版本有checksum／签章／交易恢复限制，不宣称任意升级与降级都已验收。

## 双机与远端

Mac mini固定外接键盘、MacBook内建键盘，只有MacBook开启Fn交换。两端都装同版、先用一般模式；[双机步骤](Resources/TwoMacAcceptance.md)涵盖UC两个方向及来源Terminal／目的TextEdit。CRD incoming host用Google签章身份辨识，raw Ctrl在Mac目的端翻译，已是Command通过；远端Windows viewer保持Windows Ctrl。UC隐藏metadata与不同Remote组合仍需实机验收，不承诺100%。

## 资源与验证

一般模式没有250ms／1s固定闲置轮询，只有按键、系统通知及明确deadline。HID使用XPC ownership lease和Driver回报，放开所有键后不轮询；尚有held output时保留单次安全检查。截图单轮、临时PNG直接clipboard，TIFF／PDF按预算处理。代码审查或CI不证明CPU稳定0.0–0.1%、完整App记忆体峰值、硬件交接或Driver恢复已通过。

- [操作说明](Resources/UserGuide.md)
- [人工验收八类功能](Resources/AcceptanceGuide.md)
- [外部审查逐项核对、修复与支援缺口](Docs/DualModeReview-2026-10-03.md)

## 建置

```sh
bash scripts/build-app.sh
bash scripts/package-single-app.sh
bash scripts/package-app-dmg.sh
```

产出arm64 Release App与可拖入Applications的DMG，进阶payload封装于App内。Pinned SDK准备不需要安装系统Driver；GitHub无.git ZIP仍可建置，来源会明确标记为archive，不冒用其他目录的Git revision。`bash scripts/test.sh`是开发／Hosted CI测试入口，不执行权限授予或实际硬件验收。

第三方MIT资源及官方Driver许可证保留在Resources/Licenses。未经Apple Developer／DriverKit资格，不能把官方签章dext冒充为自制WindowsMacBridge Driver。
