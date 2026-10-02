#!/bin/bash
set -euo pipefail
[[ "$#" == 2 && "$1" =~ ^[0-9]+$ && "$2" == /Applications/WindowsMacBridge.app ]] || exit 64
# Wait only for the initiating process to finish normal keyboard cleanup. A
# cancelled/stuck termination must not launch another instance or be force-killed.
for bridge_attempt in {1..75}; do
    if ! /bin/kill -0 "$1" 2>/dev/null; then
        exec /usr/bin/open -n "$2" --args --permission-relaunch
    fi
    /bin/sleep 0.2
done
exit 75
