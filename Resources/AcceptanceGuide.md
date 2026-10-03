# WindowsMacBridge build 43：人工驗收指南

程序碼回歸／CI、Release 封裝、Installed GUI 授權、實體鍵盤、跨機與資源量測是不同證據。以下尚未實機驗收。用可丟棄文字與檔案，勿在重要文件做故障測試。

## 最短開始

DMG 拖入 Applications → 一般模式 → 權限頁輔助功能 → 原生確認綠燈 → TextEdit Ctrl+C/V。啟動不應要求 Root／Driver／輸入監控，也不應自動註冊登入。首次截圖可能要求螢幕錄製；核准后重開 App 再試。不用安裝 Finder 擴充。

## 1. 快捷鍵與持鍵

TextEdit、Safari 各測 Ctrl+A/C/X/V/Z/Y/F/S/P、Ctrl+Tab、Ctrl+Shift+Tab、Ctrl+T/W／Shift+T、Ctrl+Arrow／Shift+Arrow、Home/End/Delete。先复制后按住 Ctrl 再 Tab，确认仍是分頁切换，没有残留 Command。左右 Ctrl／Shift／Alt 重叠，字母先放／修饰键先放各测一次。按住 Ctrl 在两个普通 App 来回，重复 Ctrl+C；进入 Remote、Pause、Secure Input、session锁定后放开键，回来新快捷键恢复。不要关闭系统的真正安全输入。

一般模式无法可靠按键盘 ID 分流；若另接第二把测试，两把同按相同按键时记录 aggregate flags 的限制。使用者实际环境是 Mac mini 外接＋MacBook 内建，双机按下一节。

## 2. UC／Remote／HID 分流

按 [TwoMacAcceptance.md](TwoMacAcceptance.md) 测两方向，特别是来源 Terminal→目的 TextEdit 的 Ctrl+C、两端都装 App、持键跨屏。Windows→Google Chrome Remote Desktop Host→Mac mini：在 Mac TextEdit 试 Ctrl+C/V/X/Z/A/S，已是 Command 不再翻译。Mac→Windows viewer／VM：同样组合应保持 Windows Ctrl，Alt+Tab 按客户端转发设置处理。隐藏 PID、未知复合 HID、混合 Native Mac 装置与 Remote 手动 profile 各自记录，未经操作保持「未验收」。

## 3. Finder 与窗口

两個测试文件：Ctrl+X→进新目录→Ctrl+V，应该移动一次，clipboard改变／超过5分钟不能继续旧move。F2改名、Delete垃圾桶。文件名文字编辑中的Delete应删字，未知焦点不盲删。Shift+Delete確認取消不删除；確認删除只用可丢弃文件。Alt+F4只关当前窗口，保留未储存对话，不退出整个App。一般App亮度键不能变Enter。打开多目录检查Finder延迟；没有全磁碟 FinderSync 监控，但流畅度仍须实测。

## 4. 截图与记忆体

Win+Shift+S／PrintScreen框选、Alt+PrintScreen当前窗口、Win+PrintScreen全屏存档，完成后直接 Ctrl+V／Cmd+V。CmdShift3全屏、CmdShift4选区也复制；暂停或关闭功能后恢复系统原生行为。Esc取消保持原clipboard。框选尚未结束→Pause／换backend／锁屏／切App／关功能再开，旧结果不得写入。核准／撤销 ScreenCapture 后结果不得显示伪成功；磁碟／程序／解码／编码失败各有错误。

图片预算覆盖PNG／TIFF／PDF、PDF嵌图与inline image，压缩文件小不表示可无限解码。记录5K／4K多屏截图时 **App＋screencapture＋WindowServer＋clipboard** 的峰值，分开 RSS 与 footprint；现有预算不是整体峰值保证。不要用自动化读取使用者当前clipboard或屏幕作为测试素材。

## 5. 进阶权限与Driver／安装

只有明确勾进阶才安装／连XPC。逐项授权输入监控、官方Driver；原生IOHID／driver核对才能绿灯。首装、与Karabiner共用、更新中断、timeout、需要用户批准／重开机、回滚须实机测，fixture通过不算硬件验收。切回一般应关闭自己的runtime，不停止／删除其他软件的共享Driver。权限只改本App，不重设全部TCC；ad-hoc更新重新授权属于现有签章限制。

## 6. MacBook 原生映射

仅builtIn=true的本机Apple键盘交换Fn／左Ctrl；Mac mini、USB／Bluetooth、UC／virtual不交换。正常退出还原；与他人工具Fn／Ctrl冲突要显示问题且不覆盖其他pair。强制退出后下次启动／登入应处理journal；重开机服务映射清除。睡眠／唤醒、服务重建、持键切换与restorePending都实测，不能用property setter返回true就判定成功。

## 7. 输入法与App模式

ABC与唯音各测组字、选字、Enter／Backspace／Shift／CapsLock，再测试复制。终端运行 `sleep 30` 后 Ctrl+C 应中断，IDE内嵌Terminal同样。手动App规则、快速切换、Pause应同步取消旧输入法／AX／截图任务。守护／切换热键默认关闭，手动选择不自动抢回。多个工具同时控制来源时观察冲突冷却。

## 8. 资源／封装

一般模式、关闭诊断、设置窗口关闭，开机等待两分钟，Activity Monitor观察5分钟，目标平均0.0–0.1%，不能只看一张瞬间截图。主App没有固定250ms／1s闲置timer；按键、App/session通知和明确deadline会产生正常短暂活动。记录同PID累计CPU增量、RSS与physical footprint；PID/version改变重新建baseline。自己的HID root process应无client后结束，共享Karabiner进程可能因其他软件继续运行。

分别从Git clone和无.git ZIP做Release arm64 build，核对Info版本／commit、资源allowlist、签章与DMG App→Applications拖入；登入开关只改本App。停止／移除进阶runtime保留共享Driver。没有自制MRU、thumbnail、窗口遍历切换器；AltTab只使用macOS native path。
