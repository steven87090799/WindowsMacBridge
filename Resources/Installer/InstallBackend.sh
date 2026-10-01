#!/bin/bash
set -euo pipefail
umask 077
[[ "$EUID" -eq 0 && "$#" -eq 1 ]] || { echo 'Needs administrator installation context.' >&2; exit 77; }
bridge_source="$1"
bridge_root='/Library/Application Support/WindowsMacBridge'
bridge_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.HIDHelper.plist'
bridge_driver_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.VirtualHIDService.plist'
bridge_app='/Applications/WindowsMacBridge.app'
bridge_recovery="$bridge_root/.install-recovery"
bridge_stage="$(/usr/bin/mktemp -d /private/var/tmp/WindowsMacBridge-install.XXXXXX)"
bridge_switched=0
bridge_committed=0
bridge_app_saved=0
bridge_app_changed=0
bridge_helper_running=0
bridge_driver_running=0
bridge_root_existed=0
bridge_preserve_stage=0
bridge_journal_tmp=''
[[ ! -d "$bridge_root" ]] || bridge_root_existed=1
bridge_rollback() {
    local bridge_failed=0 bridge_name bridge_destination
    /bin/launchctl bootout system "$bridge_daemon" 2>/dev/null || true
    /bin/launchctl bootout system "$bridge_driver_daemon" 2>/dev/null || true
    if [[ "$bridge_app_changed" == 1 ]]; then
        /bin/rm -rf "$bridge_app" || bridge_failed=1
        if [[ "$bridge_app_saved" == 1 ]]; then
            /usr/bin/ditto "$bridge_stage/previous/WindowsMacBridge.app" "$bridge_app" || bridge_failed=1
        fi
    fi
    for bridge_name in BridgeHIDHelper.app Licenses controller.plist; do
        bridge_destination="$bridge_root/$bridge_name"
        /bin/rm -rf "$bridge_destination" || bridge_failed=1
        if [[ -e "$bridge_stage/previous/$bridge_name" ]]; then
            /usr/bin/ditto "$bridge_stage/previous/$bridge_name" "$bridge_destination" || bridge_failed=1
        fi
    done
    for bridge_destination in "$bridge_daemon" "$bridge_driver_daemon"; do
        /bin/rm -f "$bridge_destination" || bridge_failed=1
        bridge_name="$(/usr/bin/basename "$bridge_destination")"
        if [[ -f "$bridge_stage/previous/$bridge_name" ]]; then
            /bin/cp -p "$bridge_stage/previous/$bridge_name" "$bridge_destination" || bridge_failed=1
        fi
    done
    if [[ "$bridge_helper_running" == 1 ]]; then /bin/launchctl bootstrap system "$bridge_daemon" || bridge_failed=1; fi
    if [[ "$bridge_driver_running" == 1 ]]; then /bin/launchctl bootstrap system "$bridge_driver_daemon" || bridge_failed=1; fi
    if [[ "$bridge_root_existed" == 0 ]]; then /bin/rmdir "$bridge_root" 2>/dev/null || true; fi
    return "$bridge_failed"
}
bridge_finish() {
    local bridge_result="$?"
    trap - EXIT
    if [[ "$bridge_preserve_stage" == 1 ]]; then
        echo "Protected recovery snapshot retained at $bridge_stage" >&2
        exit 1
    fi
    if [[ "$bridge_switched" == 1 && "$bridge_committed" == 0 ]]; then
        if ! bridge_rollback; then
            echo "Rollback incomplete. Protected recovery snapshot retained at $bridge_stage" >&2
            exit 1
        fi
        echo 'Installation failed; previous App, helper, pin and service state restored.' >&2
    fi
    if [[ "$bridge_switched" == 1 ]]; then
        if ! /bin/rm -f "$bridge_recovery"; then
            echo "Recovery journal cleanup failed; snapshot retained at $bridge_stage" >&2; exit 1
        fi
        /bin/sync
        if [[ "$bridge_root_existed" == 0 && "$bridge_committed" == 0 ]]; then /bin/rmdir "$bridge_root" 2>/dev/null || true; fi
    fi
    if [[ -n "$bridge_journal_tmp" ]]; then /bin/rm -f "$bridge_journal_tmp"; fi
    /bin/rm -rf "$bridge_stage"
    exit "$bridge_result"
}
trap bridge_finish EXIT
bridge_recover_interrupted() {
    [[ -e "$bridge_recovery" || -L "$bridge_recovery" ]] || return 0
    [[ -f "$bridge_recovery" && ! -L "$bridge_recovery" &&
       "$(/usr/bin/stat -f '%u' "$bridge_recovery")" == 0 ]] || { echo 'Untrusted recovery journal.' >&2; return 1; }
    local bridge_mode bridge_header bridge_saved_stage bridge_saved_pid bridge_saved_boot
    local bridge_saved_root bridge_saved_app bridge_saved_helper bridge_saved_driver bridge_new_stage
    bridge_mode="$(/usr/bin/stat -f '%Lp' "$bridge_recovery")"
    [[ "$((8#$bridge_mode & 077))" == 0 && "$(/usr/bin/wc -c < "$bridge_recovery")" -le 1024 ]] || return 1
    {
        IFS= read -r bridge_header
        IFS= read -r bridge_saved_stage
        IFS= read -r bridge_saved_pid
        IFS= read -r bridge_saved_boot
        IFS= read -r bridge_saved_root
        IFS= read -r bridge_saved_app
        IFS= read -r bridge_saved_helper
        IFS= read -r bridge_saved_driver
    } < "$bridge_recovery"
    [[ "$bridge_header" == WMB-INSTALL-1 && "$bridge_saved_stage" == /private/var/tmp/WindowsMacBridge-install.* &&
       "$bridge_saved_pid" =~ ^[0-9]+$ && "$bridge_saved_boot" =~ ^[[:xdigit:]-]{36}$ &&
       "$bridge_saved_root$bridge_saved_app$bridge_saved_helper$bridge_saved_driver" =~ ^[01]{4}$ &&
       -d "$bridge_saved_stage/previous" && ! -L "$bridge_saved_stage" &&
       "$(/usr/bin/stat -f '%u' "$bridge_saved_stage")" == 0 ]] || { echo 'Invalid recovery snapshot.' >&2; return 1; }
    bridge_mode="$(/usr/bin/stat -f '%Lp' "$bridge_saved_stage")"
    [[ "$((8#$bridge_mode & 077))" == 0 && -z "$(/usr/bin/find "$bridge_saved_stage" -type l -print -quit)" ]] || return 1
    if [[ "$bridge_saved_boot" == "$(/usr/sbin/sysctl -n kern.bootsessionuuid)" ]] && kill -0 "$bridge_saved_pid" 2>/dev/null; then
        echo 'Another installer may still be running; recovery refused.' >&2; return 1
    fi
    if [[ "$bridge_saved_app" == 1 ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_saved_stage/previous/WindowsMacBridge.app/Contents/Info.plist")" == local.WindowsMacBridge ]] || return 1
        /usr/bin/codesign --verify --strict "$bridge_saved_stage/previous/WindowsMacBridge.app"
    fi
    bridge_new_stage="$bridge_stage"; bridge_stage="$bridge_saved_stage"
    bridge_root_existed="$bridge_saved_root"; bridge_app_saved="$bridge_saved_app"; bridge_app_changed=1
    bridge_helper_running="$bridge_saved_helper"; bridge_driver_running="$bridge_saved_driver"
    bridge_preserve_stage=1
    bridge_rollback || return 1
    /bin/rm -f "$bridge_recovery"
    /bin/sync
    /bin/rm -rf "$bridge_stage"
    if [[ "$bridge_root_existed" == 0 ]]; then /bin/rmdir "$bridge_root" 2>/dev/null || true; fi
    bridge_stage="$bridge_new_stage"; bridge_preserve_stage=0
    bridge_app_saved=0; bridge_app_changed=0; bridge_helper_running=0; bridge_driver_running=0
    echo 'Recovered an interrupted App/helper/service update before proceeding.'
}
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
bridge_recover_interrupted
# The driver package is the pinned, notarized official binary. Never install a different shared version silently.
[[ "$(/usr/bin/shasum -a 256 Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg | /usr/bin/cut -d ' ' -f 1)" == ff8c7fdc5e25387c7805fc7509a0fa9cf98f69ba582704f717fddcae47424387 ]] || exit 1
/usr/sbin/pkgutil --check-signature Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg
bridge_driver_installed=''
# Missing receipt is normal. A failed enumeration or malformed existing receipt is an error.
bridge_receipts="$(/usr/sbin/pkgutil --pkgs)"
if /usr/bin/grep -Fxq org.pqrs.Karabiner-DriverKit-VirtualHIDDevice <<< "$bridge_receipts"; then
    bridge_info="$(/usr/sbin/pkgutil --pkg-info org.pqrs.Karabiner-DriverKit-VirtualHIDDevice)"
    bridge_driver_installed="$(/usr/bin/sed -n 's/^version: //p' <<< "$bridge_info")"
    [[ -n "$bridge_driver_installed" ]] || { echo 'Existing driver receipt has no version.' >&2; exit 1; }
fi
if [[ -n "$bridge_driver_installed" && "$bridge_driver_installed" != 8.6.0 ]]; then
    echo "Existing shared VirtualHID version is $bridge_driver_installed; left unchanged. Resolve driver compatibility first." >&2; exit 1
fi
# Stage every owned component and verify its identity before any service or App is switched.
/bin/mkdir -p "$bridge_stage/next" "$bridge_stage/previous"
/usr/bin/ditto WindowsMacBridge.app "$bridge_stage/next/WindowsMacBridge.app"
/usr/bin/ditto BridgeHIDHelper.app "$bridge_stage/next/BridgeHIDHelper.app"
/usr/bin/ditto Licenses "$bridge_stage/next/Licenses"
for bridge_key in CFBundleShortVersionString CFBundleVersion; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$bridge_key" WindowsMacBridge.app/Contents/Info.plist)" == \
       "$(/usr/libexec/PlistBuddy -c "Print :$bridge_key" BridgeHIDHelper.app/Contents/Info.plist)" ]] || {
        echo 'App/helper version mismatch.' >&2; exit 1;
    }
done
"$bridge_stage/next/BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper" --controller-pin \
    "$bridge_stage/next/WindowsMacBridge.app" > "$bridge_stage/next/controller.plist"
/usr/sbin/chown -R root:wheel "$bridge_stage/next"
/bin/chmod -R go-w "$bridge_stage/next"
/usr/bin/codesign --verify --strict "$bridge_stage/next/WindowsMacBridge.app"
/usr/bin/codesign --verify --strict "$bridge_stage/next/BridgeHIDHelper.app"
for bridge_name in BridgeHIDHelper.app Licenses controller.plist; do
    if [[ -e "$bridge_root/$bridge_name" ]]; then
        /usr/bin/ditto "$bridge_root/$bridge_name" "$bridge_stage/previous/$bridge_name"
    fi
done
for bridge_destination in "$bridge_daemon" "$bridge_driver_daemon"; do
    if [[ -f "$bridge_destination" ]]; then
        /bin/cp -p "$bridge_destination" "$bridge_stage/previous/$(/usr/bin/basename "$bridge_destination")"
    fi
done
if /bin/launchctl print system/local.WindowsMacBridge.HIDHelper >/dev/null 2>&1; then bridge_helper_running=1; fi
if /bin/launchctl print system/local.WindowsMacBridge.VirtualHIDService >/dev/null 2>&1; then bridge_driver_running=1; fi
if [[ -d "$bridge_app" ]]; then
    /usr/bin/ditto "$bridge_app" "$bridge_stage/previous/WindowsMacBridge.app"
    bridge_app_saved=1
fi
if [[ -z "$bridge_driver_installed" ]]; then
    /usr/sbin/installer -pkg Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg -target /
fi
/bin/mkdir -p "$bridge_root"
/usr/sbin/chown root:wheel "$bridge_root"
/bin/chmod 755 "$bridge_root"
bridge_journal_tmp="$(/usr/bin/mktemp "$bridge_root/.install-recovery.XXXXXX")"
printf 'WMB-INSTALL-1\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$bridge_stage" "$$" \
    "$(/usr/sbin/sysctl -n kern.bootsessionuuid)" "$bridge_root_existed" "$bridge_app_saved" \
    "$bridge_helper_running" "$bridge_driver_running" > "$bridge_journal_tmp"
/bin/sync
# Atomic no-clobber publication: concurrent installers cannot overwrite a live recovery owner.
/bin/ln "$bridge_journal_tmp" "$bridge_recovery"
/bin/rm -f "$bridge_journal_tmp"
bridge_journal_tmp=''
/bin/sync
bridge_switched=1
if [[ "$bridge_helper_running" == 1 ]]; then /bin/launchctl bootout system "$bridge_daemon"; fi
if [[ "$bridge_driver_running" == 1 ]]; then /bin/launchctl bootout system "$bridge_driver_daemon"; fi
/bin/mkdir -p "$bridge_root"
/usr/sbin/chown root:wheel "$bridge_root"
/bin/chmod 755 "$bridge_root"
if [[ -d "$bridge_app" ]]; then
    /bin/mv "$bridge_app" "$bridge_stage/retired-application.app"
fi
bridge_app_changed=1
/bin/mv "$bridge_stage/next/WindowsMacBridge.app" "$bridge_app"
/usr/sbin/chown -R root:wheel "$bridge_app"
/bin/chmod -R go-w "$bridge_app"
for bridge_name in BridgeHIDHelper.app Licenses; do
    /bin/rm -rf "$bridge_root/$bridge_name"
    /bin/mv "$bridge_stage/next/$bridge_name" "$bridge_root/$bridge_name"
done
/usr/sbin/chown -R root:wheel "$bridge_root/BridgeHIDHelper.app"
/bin/chmod -R go-w "$bridge_root/BridgeHIDHelper.app"
/usr/bin/install -o root -g wheel -m 644 local.WindowsMacBridge.HIDHelper.plist "$bridge_daemon"
/usr/bin/codesign --verify --strict "$bridge_app"
/bin/mv "$bridge_stage/next/controller.plist" "$bridge_root/controller.plist"
/usr/sbin/chown root:wheel "$bridge_root/controller.plist"
/bin/chmod 644 "$bridge_root/controller.plist"
/bin/launchctl bootstrap system "$bridge_daemon"
if [[ "$bridge_driver_running" == 1 ]] || ! /usr/bin/pgrep -x Karabiner-VirtualHIDDevice-Daemon >/dev/null; then
    /usr/bin/install -o root -g wheel -m 644 local.WindowsMacBridge.VirtualHIDService.plist "$bridge_driver_daemon"
    /bin/launchctl bootstrap system "$bridge_driver_daemon"
fi
if [[ "$bridge_app_saved" == 1 ]]; then
    bridge_backup="$(/usr/bin/mktemp -d "$bridge_root/PreviousApplication.XXXXXX")"
    /usr/bin/ditto "$bridge_stage/previous/WindowsMacBridge.app" "$bridge_backup/WindowsMacBridge.app"
fi
# Keep at most two owned, identifiable App backups. Never prune arbitrary user directories.
bridge_kept=0
while IFS= read -r bridge_backup; do
    [[ -d "$bridge_backup/WindowsMacBridge.app" && ! -L "$bridge_backup" ]] || continue
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_backup/WindowsMacBridge.app/Contents/Info.plist")" == local.WindowsMacBridge ]] || continue
    bridge_kept=$((bridge_kept + 1))
    if [[ "$bridge_kept" -gt 2 ]]; then /bin/rm -rf "$bridge_backup"; fi
done < <(/bin/ls -dt "$bridge_root"/PreviousApplication.* 2>/dev/null || true)
bridge_committed=1
echo 'App and pinned helper installed. Driver activation and TCC approval remain user-controlled.'
