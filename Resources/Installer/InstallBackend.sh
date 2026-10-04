#!/bin/bash
set -euo pipefail
umask 077
[[ "$EUID" -eq 0 && "$#" -eq 1 ]] || { echo 'Needs administrator installation context.' >&2; exit 77; }
bridge_source="$1"
bridge_root='/Library/Application Support/WindowsMacBridge'
bridge_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.HIDHelper.plist'
bridge_driver_daemon='/Library/LaunchDaemons/local.WindowsMacBridge.VirtualHIDService.plist'
bridge_app='/Applications/WindowsMacBridge.app'
bridge_shared_driver='/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
bridge_driver_manager='/Applications/.Karabiner-VirtualHIDDevice-Manager.app'
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
bridge_driver_changed=0
[[ ! -d "$bridge_root" ]] || bridge_root_existed=1
bridge_identity() { /usr/bin/stat -f '%d:%i' "$1" 2>/dev/null; }
# Exact-path, no-clobber, no-follow publish (renamex_np RENAME_EXCL) by the
# verified payload App: never moves into a directory or through a symlink that
# appeared at the destination, and never replaces anything there.
bridge_publish_exclusive() {
    "$bridge_payload/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge" --publish-exclusive "$1" "$2"
}
# Rollback may move only the bundle this transaction published or the App it
# found and snapshotted; anything else at the path is foreign and left alone.
bridge_owned_app_identity() {
    local bridge_found bridge_id
    bridge_found="$(bridge_identity "$bridge_app")" && [[ -n "$bridge_found" ]] || return 1
    for bridge_id in published original restored; do
        if [[ -f "$bridge_stage/$bridge_id.identity" && "$bridge_found" == "$(/bin/cat "$bridge_stage/$bridge_id.identity")" ]]; then printf '%s\n' "$bridge_found"; return 0; fi
    done
    # Snapshots from installers that predate identity records: only our own bundle.
    [[ ! -f "$bridge_stage/published.identity" && ! -f "$bridge_stage/original.identity" && ! -f "$bridge_stage/restored.identity" &&
       -d "$bridge_app" && ! -L "$bridge_app" &&
       "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_app/Contents/Info.plist" 2>/dev/null)" == local.WindowsMacBridge ]] || return 1
    printf '%s\n' "$bridge_found"
}
# No cleanup is allowed after a retirement error: even if a foreign object
# could not be put back, it remains safe in the protected transaction snapshot.
bridge_retire_owned() {
    # Durable intent precedes the rename. A killed helper/installer must not
    # leave a quarantined object eligible for a later recovery's cleanup.
    printf 'WMB-RETIRE-UNCONFIRMED\n' > "$bridge_stage/retirement.unconfirmed" || {
        bridge_preserve_stage=1; return 1; }
    /bin/sync
    if ! "$bridge_payload/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge" --retire-owned "$1" "$2" "$3"; then
        bridge_preserve_stage=1
        echo 'App retirement was not confirmed; protected recovery snapshot retained. No quarantined object will be deleted.' >&2
        return 1
    fi
    /bin/rm -f "$bridge_stage/retirement.unconfirmed" || { bridge_preserve_stage=1; return 1; }
}
bridge_restore_application() {
    local bridge_restore="$bridge_stage/retired-application.app" bridge_rejected bridge_expected
    # Interrupted before the App was retired: the original is still in place.
    if [[ "$bridge_app_saved" == 1 && -f "$bridge_stage/original.identity" &&
          "$(bridge_identity "$bridge_app")" == "$(/bin/cat "$bridge_stage/original.identity")" ]]; then
        return 0
    fi
    if [[ "$bridge_app_saved" == 1 ]]; then
        # mv keeps Finder tags (com.apple.FinderInfo), which fail strict
        # verification and used to wedge every later recovery. Older interrupted
        # transactions may only have the backup. Rebuild an attribute-free copy
        # outside /Applications before publishing a complete App.
        if [[ ! -d "$bridge_restore" ]] || ! /usr/bin/codesign --verify --strict "$bridge_restore"; then
            bridge_restore="$(/usr/bin/mktemp -d "$bridge_stage/restore.XXXXXX")/WindowsMacBridge.app" || return 1
            /usr/bin/ditto --noextattr --norsrc "$bridge_stage/previous/WindowsMacBridge.app" "$bridge_restore" || return 1
        fi
        /usr/bin/codesign --verify --strict "$bridge_restore" || { echo 'Previous App snapshot failed verification.' >&2; return 1; }
    fi
    if [[ -e "$bridge_app" || -L "$bridge_app" ]]; then
        if bridge_expected="$(bridge_owned_app_identity)"; then
            bridge_rejected="$(/usr/bin/mktemp -d "$bridge_stage/rejected.XXXXXX")" || return 1
            bridge_retire_owned "$bridge_app" "$bridge_rejected/WindowsMacBridge.app" "$bridge_expected" || return 1
        elif [[ "$bridge_app_saved" == 1 ]]; then
            echo 'A foreign object now occupies the App path; it was left untouched and recovery stays pending.' >&2; return 1
        else
            # Fresh install: nothing of ours to restore, and the foreign object is not ours to move.
            echo 'A foreign object occupies the App path; it was left untouched.' >&2
        fi
    fi
    if [[ "$bridge_app_saved" == 1 ]]; then
        bridge_identity "$bridge_restore" > "$bridge_stage/restored.identity"
        bridge_publish_exclusive "$bridge_restore" "$bridge_app" || {
            echo 'The App path was occupied while restoring; recovery stays pending.' >&2; return 1; }
    fi
}
bridge_rollback() {
    local bridge_failed=0 bridge_name bridge_destination
    /bin/launchctl bootout system "$bridge_daemon" 2>/dev/null || true
    # A compatible shared daemon can serve other clients even though we own its
    # launchd label. Keep it running through App/runtime updates and their rollback.
    if [[ "$bridge_driver_kind" != reuse || "$bridge_driver_running" == 0 ]]; then
        /bin/launchctl bootout system "$bridge_driver_daemon" 2>/dev/null || true
    fi
    if [[ "$bridge_app_changed" == 1 ]]; then
        bridge_restore_application || bridge_failed=1
    fi
    for bridge_name in BridgeHIDHelper.app Licenses controller.plist; do
        bridge_destination="$bridge_root/$bridge_name"
        /bin/rm -rf "$bridge_destination" || bridge_failed=1
        if [[ -e "$bridge_stage/previous/$bridge_name" ]]; then
            /usr/bin/ditto "$bridge_stage/previous/$bridge_name" "$bridge_destination" || bridge_failed=1
        fi
    done
    /bin/rm -rf "$bridge_root/WindowsMacBridge.app" || bridge_failed=1
    if [[ -d "$bridge_stage/previous/RuntimeApplication.app" ]]; then
        /usr/bin/ditto "$bridge_stage/previous/RuntimeApplication.app" "$bridge_root/WindowsMacBridge.app" || bridge_failed=1
    fi
    for bridge_destination in "$bridge_daemon" "$bridge_driver_daemon"; do
        /bin/rm -f "$bridge_destination" || bridge_failed=1
        bridge_name="$(/usr/bin/basename "$bridge_destination")"
        if [[ -f "$bridge_stage/previous/$bridge_name" ]]; then
            /bin/cp -p "$bridge_stage/previous/$bridge_name" "$bridge_destination" || bridge_failed=1
        fi
    done
    if [[ "$bridge_driver_changed" == 1 ]]; then bridge_driver_rollback || bridge_failed=1; fi
    # An incomplete Driver recovery must not restart either service against it.
    if [[ "$bridge_failed" == 0 ]]; then
        if [[ "$bridge_helper_running" == 1 ]]; then /bin/launchctl bootstrap system "$bridge_daemon" || bridge_failed=1; fi
        if [[ "$bridge_driver_running" == 1 ]] && ! /bin/launchctl print system/local.WindowsMacBridge.VirtualHIDService >/dev/null 2>&1; then
            /bin/launchctl bootstrap system "$bridge_driver_daemon" || bridge_failed=1
        fi
    fi
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
        echo 'Installation failed; previous App, input runtime, pin, Driver and service state restored.' >&2
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
    local bridge_saved_root bridge_saved_app bridge_saved_helper bridge_saved_driver bridge_new_stage bridge_check
    local bridge_saved_driver_kind=reuse bridge_saved_driver_version='' bridge_saved_driver_active=0 bridge_saved_phase
    bridge_mode="$(/usr/bin/stat -f '%Lp' "$bridge_recovery")"
    [[ "$((8#$bridge_mode & 077))" == 0 && "$(/usr/bin/wc -c < "$bridge_recovery")" -le 1024 ]] || {
        echo 'Recovery journal has unsafe permissions or size; nothing was changed.' >&2; return 1; }
    {
        IFS= read -r bridge_header
        IFS= read -r bridge_saved_stage
        IFS= read -r bridge_saved_pid
        IFS= read -r bridge_saved_boot
        IFS= read -r bridge_saved_root
        IFS= read -r bridge_saved_app
        IFS= read -r bridge_saved_helper
        IFS= read -r bridge_saved_driver
        if [[ "$bridge_header" == WMB-INSTALL-2 ]]; then
            IFS= read -r bridge_saved_driver_kind
            IFS= read -r bridge_saved_driver_version
            IFS= read -r bridge_saved_driver_active
        fi
    } < "$bridge_recovery"
    [[ ( "$bridge_header" == WMB-INSTALL-1 || "$bridge_header" == WMB-INSTALL-2 ) && "$bridge_saved_stage" == /private/var/tmp/WindowsMacBridge-install.* &&
       "$bridge_saved_pid" =~ ^[0-9]+$ && "$bridge_saved_boot" =~ ^[[:xdigit:]-]{36}$ &&
       "$bridge_saved_root$bridge_saved_app$bridge_saved_helper$bridge_saved_driver" =~ ^[01]{4}$ &&
       -d "$bridge_saved_stage/previous" && ! -L "$bridge_saved_stage" &&
       "$(/usr/bin/stat -f '%u' "$bridge_saved_stage")" == 0 ]] || { echo 'Invalid recovery snapshot.' >&2; return 1; }
    [[ "$bridge_saved_driver_active" =~ ^[01]$ ]] || { echo 'Invalid Driver recovery state.' >&2; return 1; }
    case "$bridge_saved_driver_kind:$bridge_saved_driver_version" in
        reuse:*|fresh:|upgrade:7.3.0) ;;
        *) echo 'Invalid Driver recovery policy.' >&2; return 1 ;;
    esac
    bridge_mode="$(/usr/bin/stat -f '%Lp' "$bridge_saved_stage")"
    [[ "$((8#$bridge_mode & 077))" == 0 && -z "$(/usr/bin/find "$bridge_saved_stage" -type l -print -quit)" ]] || {
        echo 'Recovery snapshot has unsafe permissions or symlinks; nothing was changed.' >&2; return 1; }
    # A prior retirement may have quarantined a foreign object. Never let a
    # subsequent recovery clean that snapshot, even if the App path is now free.
    [[ ! -e "$bridge_saved_stage/retirement.unconfirmed" ]] || {
        echo 'Unconfirmed App retirement requires inspection of the protected recovery snapshot; nothing was changed.' >&2; return 1; }
    if [[ "$bridge_saved_boot" == "$(/usr/sbin/sysctl -n kern.bootsessionuuid)" ]] && kill -0 "$bridge_saved_pid" 2>/dev/null; then
        echo 'Another installer may still be running; recovery refused.' >&2; return 1
    fi
    if [[ "$bridge_saved_app" == 1 ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_saved_stage/previous/WindowsMacBridge.app/Contents/Info.plist")" == local.WindowsMacBridge ]] || {
            echo 'Recovery snapshot is not this App; nothing was changed.' >&2; return 1; }
        # Snapshots from older installers may carry Finder detritus; verify the
        # same attribute-free copy that restoration publishes.
        bridge_check="$(/usr/bin/mktemp -d "$bridge_stage/check.XXXXXX")"
        /usr/bin/ditto --noextattr --norsrc "$bridge_saved_stage/previous/WindowsMacBridge.app" "$bridge_check/WindowsMacBridge.app"
        /usr/bin/codesign --verify --strict "$bridge_check/WindowsMacBridge.app" || {
            echo 'Recovery snapshot App failed verification; nothing was changed.' >&2; return 1; }
        /bin/rm -rf "$bridge_check"
    fi
    bridge_preserve_stage=1
    bridge_new_stage="$bridge_stage"; bridge_stage="$bridge_saved_stage"
    bridge_root_existed="$bridge_saved_root"; bridge_app_saved="$bridge_saved_app"; bridge_app_changed=1
    bridge_helper_running="$bridge_saved_helper"; bridge_driver_running="$bridge_saved_driver"
    bridge_driver_kind="$bridge_saved_driver_kind"; bridge_driver_old_version="$bridge_saved_driver_version"
    bridge_driver_old_active="$bridge_saved_driver_active"; bridge_driver_changed=0
    if [[ "$bridge_header" == WMB-INSTALL-2 ]]; then
        [[ -f "$bridge_stage/driver.phase" && ! -L "$bridge_stage/driver.phase" &&
           "$(/usr/bin/wc -c < "$bridge_stage/driver.phase")" -le 16 ]] || {
            echo 'Recovery snapshot has no valid Driver phase; nothing was changed.' >&2; return 1; }
        bridge_saved_phase="$(/bin/cat "$bridge_stage/driver.phase")"
        case "$bridge_saved_phase" in prepared|restored) ;; changed) bridge_driver_changed=1 ;;
            *) echo 'Invalid Driver phase in recovery snapshot.' >&2; return 1 ;; esac
    fi
    bridge_rollback || return 1
    /bin/rm -f "$bridge_recovery"
    /bin/sync
    /bin/rm -rf "$bridge_stage"
    if [[ "$bridge_root_existed" == 0 ]]; then /bin/rmdir "$bridge_root" 2>/dev/null || true; fi
    bridge_stage="$bridge_new_stage"; bridge_preserve_stage=0
    bridge_app_saved=0; bridge_app_changed=0; bridge_helper_running=0; bridge_driver_running=0
    bridge_driver_kind=reuse; bridge_driver_changed=0; bridge_driver_old_active=0; bridge_driver_old_version=''
    echo 'Recovered an interrupted App/runtime/service update before proceeding.'
}
# Copy into a private root-owned snapshot before verifying or running payload files.
/usr/bin/ditto --noextattr --norsrc "$bridge_source" "$bridge_stage/payload"
bridge_payload="$bridge_stage/payload"
# Exclusive publish is a rename; it cannot cross volumes and never falls back to copying.
[[ "$(/usr/bin/stat -f '%d' "$bridge_stage")" == "$(/usr/bin/stat -f '%d' "$(/usr/bin/dirname "$bridge_app")")" ]] || {
    echo 'Installer staging and the Applications folder are on different volumes; nothing was changed.' >&2; exit 1; }
[[ -z "$(/usr/bin/find "$bridge_payload" -type l -print -quit)" ]] || { echo 'Symlink payload rejected.' >&2; exit 1; }
cd "$bridge_payload"
/usr/bin/shasum -a 256 -c PAYLOAD-SHA256SUMS >/dev/null
# Functions must be loaded before interrupted-transaction recovery can use them.
source "$bridge_payload/DriverTransaction.sh"
/usr/bin/codesign --verify --strict WindowsMacBridge.app
source "$bridge_payload/AppProcess.sh"
if bridge_gui_running; then
    echo 'Quit WindowsMacBridge before replacing its App or keyboard driver.' >&2; exit 1
else
    bridge_process_query=$?
    [[ "$bridge_process_query" == 1 ]] || exit "$bridge_process_query"
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' WindowsMacBridge.app/Contents/Info.plist)" == 'local.WindowsMacBridge' ]]
for bridge_path in "$bridge_root" "$bridge_app" "$bridge_daemon" "$bridge_driver_daemon"; do
    [[ ! -L "$bridge_path" ]] || { echo "Symlink install destination rejected: $bridge_path" >&2; exit 1; }
done
if [[ -d "$bridge_root" ]]; then
    [[ "$(/usr/bin/stat -f '%u' "$bridge_root")" == 0 ]] || { echo 'Untrusted input runtime directory owner.' >&2; exit 1; }
    bridge_permissions="$(/usr/bin/stat -f '%Lp' "$bridge_root")"
    [[ "$((8#$bridge_permissions & 022))" == 0 ]] || { echo 'Writable input runtime directory rejected.' >&2; exit 1; }
    [[ -z "$(/usr/bin/find "$bridge_root" -type l -print -quit)" ]] || { echo 'Symlink in input runtime directory rejected.' >&2; exit 1; }
fi
bridge_verify_shared_driver() {
    local bridge_daemon_app bridge_extension bridge_path bridge_mode bridge_abi
    # Verified official version.json for these exact tags: driver 1.8.0, client
    # protocol 7. A newer or unknown package is not inferred compatible.
    # https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/v8.5.0/version.json
    case "$bridge_driver_installed" in
        8.0.0|8.1.0|8.2.0|8.3.0|8.4.0|8.5.0|8.6.0) bridge_abi=1.8.0 ;;
        7.3.0) bridge_abi=1.8.0 ;;
        *) echo "Shared VirtualHID $bridge_driver_installed has no verified ABI; no shared files were changed." >&2; return 1 ;;
    esac
    bridge_daemon_app="$bridge_shared_driver/Applications/Karabiner-VirtualHIDDevice-Daemon.app"
    bridge_extension="$bridge_driver_manager/Contents/Library/SystemExtensions/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext"
    for bridge_path in "$bridge_shared_driver" "$bridge_driver_manager"; do
        [[ -d "$bridge_path" && ! -L "$bridge_path" && "$(/usr/bin/stat -f '%u' "$bridge_path")" == 0 ]] || return 1
        bridge_mode="$(/usr/bin/stat -f '%Lp' "$bridge_path")"
        [[ "$((8#$bridge_mode & 022))" == 0 && -z "$(/usr/bin/find "$bridge_path" -type l -print -quit)" ]] || return 1
    done
    /usr/bin/codesign --verify --strict -R '=anchor apple generic and certificate leaf[subject.OU] = "G43BCU2T37" and identifier "org.pqrs.Karabiner-VirtualHIDDevice-Daemon"' "$bridge_daemon_app" || return 1
    /usr/bin/codesign --verify --strict -R '=anchor apple generic and certificate leaf[subject.OU] = "G43BCU2T37" and identifier "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"' "$bridge_extension" || return 1
    /usr/bin/codesign --verify --strict -R '=anchor apple generic and certificate leaf[subject.OU] = "G43BCU2T37" and identifier "org.pqrs.Karabiner-VirtualHIDDevice-Manager"' "$bridge_driver_manager" || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bridge_daemon_app/Contents/Info.plist")" == "$bridge_driver_installed" &&
       "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bridge_driver_manager/Contents/Info.plist")" == "$bridge_driver_installed" &&
       "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bridge_extension/Info.plist")" == "$bridge_abi" ]] || {
        echo 'Shared driver receipt and signed binary versions disagree; unchanged.' >&2; return 1;
    }
}

bridge_recover_interrupted
# Recovery must precede this check: a failed old copy may have no Info.plist.
if [[ -e "$bridge_app" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_app/Contents/Info.plist")" == 'local.WindowsMacBridge' ]] || exit 1
fi
# The driver package is the pinned, notarized official binary. Package version,
# DriverKit version and daemon protocol are separate; never downgrade a shared driver.
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

if [[ -n "$bridge_driver_installed" ]]; then bridge_verify_shared_driver; fi
# Stage every owned component and verify its identity before any service or App is switched.
/bin/mkdir -p "$bridge_stage/next" "$bridge_stage/previous"
/usr/bin/ditto WindowsMacBridge.app "$bridge_stage/next/WindowsMacBridge.app"
/usr/bin/ditto WindowsMacBridge.app "$bridge_stage/next/RuntimeApplication.app"
/usr/bin/ditto Licenses "$bridge_stage/next/Licenses"
"$bridge_stage/next/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge" --controller-pin \
    "$bridge_stage/next/WindowsMacBridge.app" > "$bridge_stage/next/controller.plist"
/usr/sbin/chown -R root:wheel "$bridge_stage/next"
# Finish ownership and public-software permissions in the private staging area.
# macOS App Management may reject even root chmod/chown after App publication.
/bin/chmod -R a+rX,go-w "$bridge_stage/next"
/usr/bin/codesign --verify --strict "$bridge_stage/next/WindowsMacBridge.app"
/usr/bin/codesign --verify --strict "$bridge_stage/next/RuntimeApplication.app"
# Preserve both the legacy helper and the unified runtime for transactional migration.
for bridge_owned in WindowsMacBridge.app BridgeHIDHelper.app; do
    if [[ -e "$bridge_root/$bridge_owned" ]]; then
        bridge_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bridge_root/$bridge_owned/Contents/Info.plist")"
        [[ ( "$bridge_owned" == WindowsMacBridge.app && "$bridge_id" == local.WindowsMacBridge ) ||
           ( "$bridge_owned" == BridgeHIDHelper.app && "$bridge_id" == local.WindowsMacBridge.HIDHelper ) ]] || exit 1
    fi
done
if [[ -d "$bridge_root/WindowsMacBridge.app" ]]; then
    /usr/bin/ditto "$bridge_root/WindowsMacBridge.app" "$bridge_stage/previous/RuntimeApplication.app"
fi
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
    # Attribute-free and verified before anything is switched, so rollback can
    # always publish it (a Finder tag on the installed App fails --strict).
    bridge_identity "$bridge_app" > "$bridge_stage/original.identity"
    /usr/bin/ditto --noextattr --norsrc "$bridge_app" "$bridge_stage/previous/WindowsMacBridge.app"
    /usr/bin/codesign --verify --strict "$bridge_stage/previous/WindowsMacBridge.app" || {
        echo 'The installed App cannot be snapshotted for rollback; nothing was switched.' >&2; exit 1; }
    [[ "$(bridge_identity "$bridge_app")" == "$(/bin/cat "$bridge_stage/original.identity")" ]] || {
        echo 'The installed App changed during snapshot; nothing was switched.' >&2; exit 1; }
    bridge_app_saved=1
fi
bridge_driver_prepare
/bin/mkdir -p "$bridge_root"
/usr/sbin/chown root:wheel "$bridge_root"
/bin/chmod 755 "$bridge_root"
bridge_journal_tmp="$(/usr/bin/mktemp "$bridge_root/.install-recovery.XXXXXX")"
printf 'WMB-INSTALL-2\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$bridge_stage" "$$" \
    "$(/usr/sbin/sysctl -n kern.bootsessionuuid)" "$bridge_root_existed" "$bridge_app_saved" \
    "$bridge_helper_running" "$bridge_driver_running" "$bridge_driver_kind" "$bridge_driver_old_version" \
    "$bridge_driver_old_active" > "$bridge_journal_tmp"
/bin/sync
# Atomic no-clobber publication: concurrent installers cannot overwrite a live recovery owner.
/bin/ln "$bridge_journal_tmp" "$bridge_recovery"
/bin/rm -f "$bridge_journal_tmp"
bridge_journal_tmp=''
/bin/sync
bridge_switched=1
if [[ "$bridge_helper_running" == 1 ]]; then /bin/launchctl bootout system "$bridge_daemon"; fi
bridge_driver_check_foreign_clients
if [[ "$bridge_driver_running" == 1 && "$bridge_driver_kind" != reuse ]]; then /bin/launchctl bootout system "$bridge_driver_daemon"; fi
bridge_driver_switch
/bin/mkdir -p "$bridge_root"
/usr/sbin/chown root:wheel "$bridge_root"
/bin/chmod 755 "$bridge_root"
if [[ -e "$bridge_app" || -L "$bridge_app" ]]; then
    # Retire only the App that was snapshotted, never an object that replaced it.
    [[ -f "$bridge_stage/original.identity" && "$(bridge_identity "$bridge_app")" == "$(/bin/cat "$bridge_stage/original.identity")" ]] || {
        echo 'The installed App changed during installation; not switching.' >&2; exit 1; }
    bridge_retire_owned "$bridge_app" "$bridge_stage/retired-application.app" "$(/bin/cat "$bridge_stage/original.identity")" || exit 1
fi
bridge_app_changed=1
# /Applications is admin-group writable: re-check immediately before publishing,
# and never let mv move the bundle INTO a directory or symlink at that path.
# rename preserves the inode, so this identity marks exactly what we publish.
bridge_identity "$bridge_stage/next/WindowsMacBridge.app" > "$bridge_stage/published.identity"
bridge_publish_exclusive "$bridge_stage/next/WindowsMacBridge.app" "$bridge_app" || {
    echo 'Install destination is occupied; not publishing.' >&2; exit 1; }
for bridge_name in WindowsMacBridge.app BridgeHIDHelper.app; do
    if [[ -e "$bridge_root/$bridge_name" ]]; then
        /bin/mv "$bridge_root/$bridge_name" "$bridge_stage/retired-$bridge_name"
    fi
done
/bin/mv "$bridge_stage/next/RuntimeApplication.app" "$bridge_root/WindowsMacBridge.app"
/bin/rm -rf "$bridge_root/Licenses"
/bin/mv "$bridge_stage/next/Licenses" "$bridge_root/Licenses"
/usr/bin/codesign --verify --strict "$bridge_root/WindowsMacBridge.app"
/usr/bin/install -o root -g wheel -m 644 local.WindowsMacBridge.HIDHelper.plist "$bridge_daemon"
/usr/bin/codesign --verify --strict "$bridge_app"
/bin/mv "$bridge_stage/next/controller.plist" "$bridge_root/controller.plist"
/usr/sbin/chown root:wheel "$bridge_root/controller.plist"
/bin/chmod 644 "$bridge_root/controller.plist"
/bin/launchctl bootstrap system "$bridge_daemon"
if [[ "$bridge_driver_kind" == reuse && "$bridge_driver_running" == 1 ]]; then
    if ! /bin/launchctl print system/local.WindowsMacBridge.VirtualHIDService >/dev/null 2>&1; then
        /bin/launchctl bootstrap system "$bridge_driver_daemon"
    fi
elif [[ "$bridge_driver_running" == 1 ]] || ! /usr/bin/pgrep -x Karabiner-VirtualHIDDevice-Daemon >/dev/null; then
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
echo 'Unified App and keyboard runtime installed. Driver activation and TCC approval remain user-controlled.'
