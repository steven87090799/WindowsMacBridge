#!/bin/bash
set -euo pipefail
[[ "$#" == 1 ]] || exit 64
bridge_uninstaller="$1/Contents/Resources/BackendPayload/UninstallBackend.sh"
[[ -f "$bridge_uninstaller" && ! -L "$bridge_uninstaller" ]] || exit 1
/usr/bin/osascript - "$bridge_uninstaller" <<'APPLESCRIPT'
on run arguments
    do shell script "/bin/bash " & quoted form of item 1 of arguments with administrator privileges
end run
APPLESCRIPT
