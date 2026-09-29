#!/bin/bash
set -euo pipefail
[[ "$EUID" -eq 0 && "$#" -eq 1 ]] || { echo 'Needs administrator installation context.' >&2; exit 77; }
bridge_source="$1"
bridge_root='/Library/Application Support/WindowsMacBridge'
bridge_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.HIDHelper.plist'
bridge_driver_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.VirtualHIDService.plist'
bridge_app='/Applications/WindowsMacBridge.app'
bridge_stage="$(/usr/bin/mktemp -d /private/var/tmp/WindowsMacBridge-install.XXXXXX)"
trap '/bin/rm -rf "$bridge_stage"' EXIT
# Copy into a private root-owned snapshot before verifying or running payload files.
/usr/bin/ditto --noextattr --norsrc "$bridge_source" "$bridge_stage/payload"
bridge_payload="$bridge_stage/payload"
[[ -z "$(/usr/bin/find "$bridge_payload" -type l -print -quit)" ]] || { echo 'Symlink payload rejected.' >&2; exit 1; }
cd "$bridge_payload"
/usr/bin/shasum -a 256 -c PAYLOAD-SHA256SUMS
/usr/bin/codesign --verify --strict WindowsMacBridge.app
/usr/bin/codesign --verify --strict BridgeHIDHelper.app
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' WindowsMacBridge.app/Contents/Info.plist)" == 'local.WindowsMacBridge' ]]
for bridge_path in "$bridge_root" "$bridge_app" "$bridge_daemon" "$bridge_driver_daemon"; do
    [[ ! -L "$bridge_path" ]] || { echo "Symlink install destination rejected: $bridge_path" >&2; exit 1; }
done
if [[ -e "$bridge_app" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_app/Contents/Info.plist")" == 'local.WindowsMacBridge' ]] || exit 1
fi
if [[ -d "$bridge_root" ]]; then
    [[ "$(/usr/bin/stat -f '%u' "$bridge_root")" == 0 ]] || { echo 'Untrusted helper directory owner.' >&2; exit 1; }
    bridge_permissions="$(/usr/bin/stat -f '%Lp' "$bridge_root")"
    [[ "$((8#$bridge_permissions & 022))" == 0 ]] || { echo 'Writable helper directory rejected.' >&2; exit 1; }
    [[ -z "$(/usr/bin/find "$bridge_root" -type l -print -quit)" ]] || { echo 'Symlink in helper directory rejected.' >&2; exit 1; }
fi
# The driver package is the pinned, notarized official binary. Never install a different shared version silently.
[[ "$(/usr/bin/shasum -a 256 Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg | /usr/bin/cut -d ' ' -f 1)" == ff8c7fdc5e25387c7805fc7509a0fa9cf98f69ba582704f717fddcae47424387 ]] || exit 1
/usr/sbin/pkgutil --check-signature Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg
bridge_driver_installed="$(/usr/sbin/pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice 2>/dev/null | /usr/bin/sed -n 's/^version: //p')"
if [[ -n "$bridge_driver_installed" && "$bridge_driver_installed" != 8.6.0 ]]; then
    echo "Existing shared VirtualHID version is $bridge_driver_installed; left unchanged. Resolve driver compatibility first." >&2; exit 1
fi
if [[ -z "$bridge_driver_installed" ]]; then
    /usr/sbin/installer -pkg Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg -target /
fi
/bin/launchctl bootout system "$bridge_daemon" 2>/dev/null || true
/bin/mkdir -p "$bridge_root"
/usr/sbin/chown root:wheel "$bridge_root"
/bin/chmod 755 "$bridge_root"
if [[ -d "$bridge_app" ]]; then
    bridge_backup="$(/usr/bin/mktemp -d "$bridge_root/PreviousApplication.XXXXXX")"
    /bin/mv "$bridge_app" "$bridge_backup/WindowsMacBridge.app"
fi
/usr/bin/ditto WindowsMacBridge.app "$bridge_app"
/usr/sbin/chown -R root:wheel "$bridge_app"
/bin/chmod -R go-w "$bridge_app"
/usr/bin/ditto BridgeHIDHelper.app "$bridge_root/BridgeHIDHelper.app"
/usr/sbin/chown -R root:wheel "$bridge_root/BridgeHIDHelper.app"
/bin/chmod -R go-w "$bridge_root/BridgeHIDHelper.app"
/usr/bin/ditto Licenses "$bridge_root/Licenses"
/usr/bin/install -o root -g wheel -m 644 local.WindowsMacBridge.HIDHelper.plist "$bridge_daemon"
/usr/bin/codesign --verify --strict "$bridge_app"
"$bridge_root/BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper" --controller-pin "$bridge_app" > "$bridge_root/controller.plist"
/usr/sbin/chown root:wheel "$bridge_root/controller.plist"
/bin/chmod 644 "$bridge_root/controller.plist"
/bin/launchctl bootstrap system "$bridge_daemon"
if ! /usr/bin/pgrep -x Karabiner-VirtualHIDDevice-Daemon >/dev/null; then
    /usr/bin/install -o root -g wheel -m 644 local.WindowsMacBridge.VirtualHIDService.plist "$bridge_driver_daemon"
    /bin/launchctl bootout system "$bridge_driver_daemon" 2>/dev/null || true
    /bin/launchctl bootstrap system "$bridge_driver_daemon"
fi
echo 'App and pinned helper installed. Driver activation and TCC approval remain user-controlled.'
