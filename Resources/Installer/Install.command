#!/bin/bash
set -euo pipefail
bridge_package="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' 'WindowsMacBridge HID 開發測試版安裝' '將安裝 App、root helper 及官方 VirtualHID Driver。請先結束 WindowsMacBridge 與 Karabiner 的鍵盤映射。'
if /usr/bin/pgrep -x WindowsMacBridge >/dev/null; then
    echo '請先從 Menu Bar 結束 WindowsMacBridge，再執行安裝。'; exit 1
fi
/usr/bin/osascript - "$bridge_package/InstallBackend.sh" "$bridge_package" <<'APPLESCRIPT'
on run arguments
    do shell script "/bin/bash " & quoted form of item 1 of arguments & " " & quoted form of item 2 of arguments with administrator privileges
end run
APPLESCRIPT
"$bridge_package/ActivateDriver.command"
printf '%s\n' '安裝完成。請依 READ-ME-FIRST.md 核准 Driver／輸入監控，再開啟 WindowsMacBridge。預設不會自動啟用鍵盤擷取。'
/usr/bin/open /Applications/WindowsMacBridge.app
