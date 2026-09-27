#!/bin/bash
set -euo pipefail
/usr/bin/osascript <<'APPLESCRIPT'
do shell script "/bin/launchctl bootout system/local.WindowsMacBridge.HIDHelper" with administrator privileges
APPLESCRIPT
echo 'HID helper 已停止；裝置擷取已解除。下次啟用需重新執行 Install.command。'
