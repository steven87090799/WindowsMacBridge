#!/bin/bash
set -euo pipefail
bridge_manager='/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager'
[[ -x "$bridge_manager" ]] || { echo '請先執行 Install.command。'; exit 1; }
"$bridge_manager" activate
echo '請依 macOS 提示核准系統延伸功能；若系統要求重新啟動，請重啟後再啟用 WindowsMacBridge。'
