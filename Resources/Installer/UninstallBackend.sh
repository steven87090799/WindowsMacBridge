#!/bin/bash
set -euo pipefail
[[ "$EUID" -eq 0 ]] || exit 77
bridge_root='/Library/Application Support/WindowsMacBridge'
bridge_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.HIDHelper.plist'
bridge_driver_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.VirtualHIDService.plist'
[[ ! -L "$bridge_root" && ! -L "$bridge_daemon" && ! -L "$bridge_driver_daemon" ]] || exit 1
if [[ -e "$bridge_root/.install-recovery" || -L "$bridge_root/.install-recovery" ]]; then
    echo 'An interrupted update needs recovery. Run Install.command before uninstalling.' >&2
    exit 1
fi
/bin/launchctl bootout system "$bridge_daemon" 2>/dev/null || true
if /bin/launchctl print system/local.WindowsMacBridge.HIDHelper >/dev/null 2>&1; then
    echo 'Bridge helper is still registered; refusing to remove its files.' >&2
    exit 1
fi
# The daemon may have acquired other clients since Bridge installed its plist.
# A client-count snapshot cannot exclude a concurrent connection. Preserve the
# shared service and its registration; shared-driver removal is a separate step.
for bridge_file in "$bridge_root/BridgeHIDHelper" "$bridge_root/controller.plist" "$bridge_daemon"; do
    [[ ! -L "$bridge_file" ]] || exit 1
    if [[ -f "$bridge_file" ]]; then
        [[ "$(/usr/bin/stat -f '%u' "$bridge_file")" == 0 ]] || exit 1
        /bin/rm "$bridge_file"
    fi
done
bridge_helper="$bridge_root/BridgeHIDHelper.app"
if [[ -d "$bridge_helper" ]]; then
    [[ ! -L "$bridge_helper" && "$(/usr/bin/stat -f '%u' "$bridge_helper")" == 0 ]] || exit 1
    [[ -z "$(/usr/bin/find "$bridge_helper" -type l -print -quit)" ]] || exit 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_helper/Contents/Info.plist")" == local.WindowsMacBridge.HIDHelper ]] || exit 1
    /bin/rm -rf "$bridge_helper"
fi
echo 'Bridge helper removed. Shared VirtualHID driver and service registration were preserved.'
