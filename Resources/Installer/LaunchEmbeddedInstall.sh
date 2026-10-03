#!/bin/bash
set -euo pipefail
umask 077
[[ "$#" == 1 ]] || exit 64
bridge_source_app="$1"
[[ -d "$bridge_source_app/Contents/Resources/BackendPayload" ]] || exit 1
/bin/mkdir -p "$HOME/Library/Logs/WindowsMacBridge"
bridge_log="$(/usr/bin/mktemp "$HOME/Library/Logs/WindowsMacBridge/install.XXXXXX")"
bridge_finish_setup() {
    local bridge_result=$?
    trap - EXIT
    if [[ "$bridge_result" != 0 ]]; then
        /usr/bin/osascript - "$bridge_log" <<'APPLESCRIPT' || true
on run arguments
    display alert "背景元件安裝尚未完成" message ("背景元件準備失敗。請保留這份安裝記錄以確認原因：" & item 1 of arguments) as critical
end run
APPLESCRIPT
        # Auto-install must not reopen after Cancel and repeat authentication.
    fi
    exit "$bridge_result"
}
trap bridge_finish_setup EXIT
# Installation must not replace an executing App or overlap its key ownership.
source "$bridge_source_app/Contents/Resources/AppProcess.sh"
for bridge_attempt in {1..50}; do
    if bridge_gui_running; then /bin/sleep 0.2
    else
        bridge_query=$?
        [[ "$bridge_query" == 1 ]] || exit "$bridge_query"
        break
    fi
done
if bridge_gui_running; then exit 1
else
    bridge_query=$?
    [[ "$bridge_query" == 1 ]] || exit "$bridge_query"
fi
# Root never executes or stages a user-writable file in place: bash reads a
# script incrementally, so a same-user process could rewrite it mid-run, and a
# user-built payload/manifest is not bound to the signed App. The bootstrap is
# fixed at authorization time; it copies the App into a private root-owned
# stage, verifies that copy and builds the payload only from its sealed
# BackendPayload. Ad-hoc signatures prove consistency, not publisher identity;
# release builds need a Developer ID requirement here.
read -r -d '' bridge_bootstrap <<'BOOTSTRAP' || true
set -euo pipefail
umask 077
bridge_boot="$(/usr/bin/mktemp -d /private/var/tmp/WindowsMacBridge-boot.XXXXXX)"
trap '/bin/rm -rf "$bridge_boot"' EXIT
/usr/bin/ditto --noextattr --norsrc "$1" "$bridge_boot/WindowsMacBridge.app"
/usr/bin/codesign --verify --strict -R '=identifier "local.WindowsMacBridge"' "$bridge_boot/WindowsMacBridge.app"
/usr/bin/ditto --noextattr --norsrc "$bridge_boot/WindowsMacBridge.app/Contents/Resources/BackendPayload" "$bridge_boot/payload"
/bin/mv "$bridge_boot/WindowsMacBridge.app" "$bridge_boot/payload/WindowsMacBridge.app"
(cd "$bridge_boot/payload" && /usr/bin/find . -type f -exec /usr/bin/shasum -a 256 {} + > "$bridge_boot/manifest")
/bin/mv "$bridge_boot/manifest" "$bridge_boot/payload/PAYLOAD-SHA256SUMS"
/bin/bash "$bridge_boot/payload/WindowsMacBridge.app/Contents/Resources/BackendPayload/InstallBackend.sh" "$bridge_boot/payload"
BOOTSTRAP
/usr/bin/osascript - "$bridge_bootstrap" "$bridge_source_app" > "$bridge_log" 2>&1 <<'APPLESCRIPT'
on run arguments
    do shell script "/bin/bash -c " & quoted form of item 1 of arguments & " WindowsMacBridge-install " & quoted form of item 2 of arguments & " 1>&2" with administrator privileges
end run
APPLESCRIPT
/usr/bin/open -n /Applications/WindowsMacBridge.app
