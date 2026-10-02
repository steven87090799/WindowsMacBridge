#!/bin/bash
set -euo pipefail
umask 077
[[ "$#" == 1 ]] || exit 64
bridge_source_app="$1"
bridge_resources="$bridge_source_app/Contents/Resources"
bridge_work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/WindowsMacBridge-setup.XXXXXX")"
bridge_payload="$bridge_work/payload"
/bin/mkdir -p "$HOME/Library/Logs/WindowsMacBridge"
bridge_log="$(/usr/bin/mktemp "$HOME/Library/Logs/WindowsMacBridge/install.XXXXXX")"
bridge_finish_setup() {
    local bridge_result=$?
    trap - EXIT
    /bin/rm -rf "$bridge_work"
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
# Always snapshot outside the App; copying a payload into its own bundle would
# recurse. The administrator installer takes another private root-owned snapshot.
/usr/bin/ditto --noextattr --norsrc "$bridge_resources/BackendPayload" "$bridge_payload"
/usr/bin/ditto --noextattr --norsrc "$bridge_source_app" "$bridge_payload/WindowsMacBridge.app"
(
    cd "$bridge_payload"
    /usr/bin/find . -type f -exec /usr/bin/shasum -a 256 {} + > "$bridge_work/manifest"
)
/bin/mv "$bridge_work/manifest" "$bridge_payload/PAYLOAD-SHA256SUMS"
# Installation must not replace an executing App or overlap its key ownership.
for bridge_attempt in {1..50}; do
    if /usr/bin/pgrep -x WindowsMacBridge >/dev/null; then /bin/sleep 0.2
    else
        bridge_query=$?
        [[ "$bridge_query" == 1 ]] || exit "$bridge_query"
        break
    fi
done
if /usr/bin/pgrep -x WindowsMacBridge >/dev/null; then exit 1; fi
/usr/bin/osascript - "$bridge_payload/InstallBackend.sh" "$bridge_payload" > "$bridge_log" 2>&1 <<'APPLESCRIPT'
on run arguments
    do shell script "/bin/bash " & quoted form of item 1 of arguments & " " & quoted form of item 2 of arguments & " 1>&2" with administrator privileges
end run
APPLESCRIPT
/usr/bin/open /Applications/WindowsMacBridge.app
