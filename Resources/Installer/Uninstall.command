#!/bin/bash
set -euo pipefail
bridge_package="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/osascript - "$bridge_package/UninstallBackend.sh" <<'APPLESCRIPT'
on run arguments
    do shell script "/bin/bash " & quoted form of item 1 of arguments with administrator privileges
end run
APPLESCRIPT
echo 'Helper 已移除。App、設定與共用官方 Driver 保留。'
