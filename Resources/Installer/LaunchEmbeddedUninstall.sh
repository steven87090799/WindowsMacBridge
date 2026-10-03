#!/bin/bash
set -euo pipefail
[[ "$#" == 1 ]] || exit 64
[[ -f "$1/Contents/Resources/BackendPayload/UninstallBackend.sh" && ! -L "$1/Contents/Resources/BackendPayload/UninstallBackend.sh" ]] || exit 1
# Same boundary as installation: root runs only a sealed copy in a private stage.
read -r -d '' bridge_bootstrap <<'BOOTSTRAP' || true
set -euo pipefail
umask 077
bridge_boot="$(/usr/bin/mktemp -d /private/var/tmp/WindowsMacBridge-boot.XXXXXX)"
trap '/bin/rm -rf "$bridge_boot"' EXIT
/usr/bin/ditto --noextattr --norsrc "$1" "$bridge_boot/WindowsMacBridge.app"
/usr/bin/codesign --verify --strict -R '=identifier "local.WindowsMacBridge"' "$bridge_boot/WindowsMacBridge.app"
/bin/bash "$bridge_boot/WindowsMacBridge.app/Contents/Resources/BackendPayload/UninstallBackend.sh"
BOOTSTRAP
/usr/bin/osascript - "$bridge_bootstrap" "$1" <<'APPLESCRIPT'
on run arguments
    do shell script "/bin/bash -c " & quoted form of item 1 of arguments & " WindowsMacBridge-uninstall " & quoted form of item 2 of arguments with administrator privileges
end run
APPLESCRIPT
