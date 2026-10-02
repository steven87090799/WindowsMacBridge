#!/bin/bash
# Sourced only from the private, checksum-verified installer payload. No runtime polling.
bridge_driver_kind=reuse
bridge_driver_changed=0
bridge_driver_old_active=0
bridge_driver_old_version=''
bridge_driver_old_pkg='Karabiner-DriverKit-VirtualHIDDevice-7.3.0.pkg'
bridge_driver_old_sha=4ccd9b11628f4c319b17452927827a8313728fe60292e4f789ef4ba626e09ba0
bridge_driver_identifier=org.pqrs.Karabiner-DriverKit-VirtualHIDDevice

bridge_driver_write_phase() {
    local bridge_phase_temp
    case "$1" in prepared|changed|restored) ;; *) return 1 ;; esac
    bridge_phase_temp="$(/usr/bin/mktemp "$bridge_stage/.driver-phase.XXXXXX")" || return 1
    printf '%s\n' "$1" > "$bridge_phase_temp" || return 1
    /bin/sync
    /bin/mv "$bridge_phase_temp" "$bridge_stage/driver.phase" || return 1
    /bin/sync
}

bridge_driver_active() {
    local bridge_rows
    bridge_rows="$(/usr/bin/systemextensionsctl list)" || return 2
    /usr/bin/grep -F "$bridge_driver_identifier" <<< "$bridge_rows" |
        /usr/bin/grep -F G43BCU2T37 | /usr/bin/grep -F "($1/$1)" |
        /usr/bin/grep -Fq '[activated enabled]'
}
bridge_driver_absent() {
    local bridge_rows
    bridge_rows="$(/usr/bin/systemextensionsctl list)" || return 1
    # A successful manager exit may leave a pending approval/reboot registration.
    # Keep the manager, receipt and recovery journal until OS removal is confirmed.
    if /usr/bin/grep -Fq "$bridge_driver_identifier" <<< "$bridge_rows"; then
        echo 'Driver registration still exists; recovery retained until system removal completes.' >&2
        return 1
    fi
}
bridge_driver_run_manager() {
    local bridge_operation="$1" bridge_log="$2" bridge_result=0
    local bridge_executable="$bridge_driver_manager/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    /usr/bin/codesign --verify --strict "$bridge_driver_manager" || return 1
    # One bounded process group; timeout kills the manager and its descendants.
    # The runner enters the GUI user's bootstrap/credentials, never approves TCC.
    "$bridge_payload/DriverProcessRunner" "$bridge_executable" "$bridge_operation" "$bridge_log" || bridge_result=$?
    if [[ "$bridge_result" != 0 ]]; then
        echo "Driver manager $bridge_operation failed (exit $bridge_result)." >&2
        /usr/bin/tail -n 40 "$bridge_log" >&2
    fi
    # A zero exit can mean approval/reboot pending. It is not activation proof.
    if /usr/bin/grep -Fq 'requires reboot' "$bridge_log"; then return 1; fi
    return "$bridge_result"
}
bridge_driver_verify_old_package() {
    local bridge_pkg="$1"
    [[ -f "$bridge_pkg" && ! -L "$bridge_pkg" &&
        "$(/usr/bin/shasum -a 256 "$bridge_pkg" | /usr/bin/cut -d ' ' -f 1)" == "$bridge_driver_old_sha" ]] || return 1
    /usr/sbin/pkgutil --check-signature "$bridge_pkg"
}
bridge_driver_prepare() {
    bridge_driver_old_version="$bridge_driver_installed"
    if [[ -z "$bridge_driver_installed" ]]; then
        # No receipt is a valid first install only if shared binaries are absent.
        [[ ! -e "$bridge_shared_driver" && ! -L "$bridge_shared_driver" &&
           ! -e "$bridge_driver_manager" && ! -L "$bridge_driver_manager" ]] || {
            echo 'Unreceipted shared Driver files found; refusing to overwrite another installation.' >&2; return 1;
        }
        local bridge_existing_extensions bridge_query
        bridge_existing_extensions="$(/usr/bin/systemextensionsctl list)" || return 1
        if /usr/bin/grep -Fq "$bridge_driver_identifier" <<< "$bridge_existing_extensions"; then
            echo 'An existing Driver registration has no receipt; repair its owning installation first.' >&2; return 1
        fi
        if /usr/bin/pgrep -x Karabiner-VirtualHIDDevice-Daemon >/dev/null; then
            echo 'A foreign Driver daemon is running; first installation refused.' >&2; return 1
        else bridge_query=$?; [[ "$bridge_query" == 1 ]] || return 1; fi
        bridge_driver_kind=fresh
    elif [[ "$bridge_driver_installed" == 7.3.0 ]]; then
        bridge_driver_kind=upgrade
        [[ ! -d /Applications/Karabiner-Elements.app ]] || {
            echo 'Karabiner also owns the old Driver; update its compatible client first.' >&2; return 1;
        }
        bridge_driver_verify_old_package "$bridge_payload/Driver/$bridge_driver_old_pkg" || return 1
        /bin/cp -p "$bridge_payload/Driver/$bridge_driver_old_pkg" "$bridge_stage/previous/$bridge_driver_old_pkg" || return 1
        /usr/bin/ditto "$bridge_shared_driver" "$bridge_stage/previous/SharedDriver" || return 1
        /usr/bin/ditto "$bridge_driver_manager" "$bridge_stage/previous/DriverManager.app" || return 1
        if bridge_driver_active 1.8.0; then bridge_driver_old_active=1
        else [[ "$?" == 1 ]] || return 1; fi
    fi
    bridge_driver_write_phase prepared
}
bridge_driver_check_foreign_clients() {
    [[ "$bridge_driver_kind" != upgrade ]] && return 0
    local bridge_pid bridge_connections bridge_count bridge_error
    if bridge_pid="$(/usr/bin/pgrep -x Karabiner-VirtualHIDDevice-Daemon)"; then
        [[ "$bridge_pid" =~ ^[0-9]+$ && "$bridge_driver_running" == 1 ]] || {
            echo 'A foreign Driver daemon is running; shared upgrade refused.' >&2; return 1;
        }
        bridge_connections="$(/usr/sbin/lsof -n -P -a -p "$bridge_pid" -U -F f)" || return 1
        bridge_count="$(/usr/bin/grep -c '^f' <<< "$bridge_connections")"
        [[ "$bridge_count" == 1 ]] || {
            echo 'Other clients still use the shared Driver; upgrade refused.' >&2; return 1;
        }
    else
        bridge_error=$?; [[ "$bridge_error" == 1 ]] || return 1
    fi
}
bridge_driver_switch() {
    [[ "$bridge_driver_kind" != reuse ]] || return 0
    # Publish the mutation intent before installer can leave even a partial file.
    bridge_driver_write_phase changed || return 1
    bridge_driver_changed=1
    /usr/sbin/installer -pkg "$bridge_payload/Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg" -target / || return 1
    bridge_driver_installed=8.6.0
    bridge_verify_shared_driver || return 1
    if [[ "$bridge_driver_kind" == fresh ]]; then
        # First installation and OS approval are separate user actions. An
        # inactive driver cannot make DeviceCapture ready or seize a keyboard.
        # Existing shared-driver upgrades retain their activation/rollback gate.
        echo 'Driver files installed. Enable/approve the official Driver from the App when ready.'
        return 0
    fi
    if bridge_driver_active 1.8.0; then :
    else
        [[ "$?" == 1 ]] || return 1
        bridge_driver_run_manager activate "$bridge_stage/driver-activate.log" || return 1
        bridge_driver_active 1.8.0 || return 1
    fi
}
bridge_driver_rollback() {
    [[ "$bridge_driver_changed" == 1 ]] || return 0
    local bridge_info bridge_current='' bridge_registered
    if bridge_info="$(/usr/sbin/pkgutil --pkg-info "$bridge_driver_identifier" 2>/dev/null)"; then
        bridge_current="$(/usr/bin/sed -n 's/^version: //p' <<< "$bridge_info")"
    else
        local bridge_receipts
        bridge_receipts="$(/usr/sbin/pkgutil --pkgs)" || return 1
        if /usr/bin/grep -Fxq "$bridge_driver_identifier" <<< "$bridge_receipts"; then return 1; fi
    fi
    [[ -z "$bridge_current" || "$bridge_current" == 8.6.0 || "$bridge_current" == "$bridge_driver_old_version" ]] || {
        echo 'Shared Driver was changed by another installer; recovery snapshot retained.' >&2; return 1;
    }
    if [[ "$bridge_driver_kind" == upgrade ]]; then
        bridge_driver_verify_old_package "$bridge_stage/previous/$bridge_driver_old_pkg" || return 1
        /usr/sbin/installer -pkg "$bridge_stage/previous/$bridge_driver_old_pkg" -target / || return 1
        # Restore the exact previously signed bytes, not only the old version label.
        /bin/rm -rf "$bridge_shared_driver" "$bridge_driver_manager" || return 1
        /usr/bin/ditto "$bridge_stage/previous/SharedDriver" "$bridge_shared_driver" || return 1
        /usr/bin/ditto "$bridge_stage/previous/DriverManager.app" "$bridge_driver_manager" || return 1
        bridge_driver_installed=7.3.0
        bridge_verify_shared_driver || return 1
        if [[ "$bridge_driver_old_active" == 1 ]]; then
            # Force replacement is necessary for a downgrade after activation.
            if ! bridge_driver_run_manager forceActivate "$bridge_stage/driver-restore.log"; then
                # The manager cancels a request for an already-active same version.
                /usr/bin/grep -Fq 'is already installed' "$bridge_stage/driver-restore.log" || return 1
            fi
            bridge_driver_active 1.8.0 || return 1
        else
            bridge_registered="$(/usr/bin/systemextensionsctl list)" || return 1
            if /usr/bin/grep -Fq "$bridge_driver_identifier" <<< "$bridge_registered"; then
                bridge_driver_run_manager deactivate "$bridge_stage/driver-restore.log" || return 1
                bridge_driver_absent || return 1
            fi
        fi
    elif [[ "$bridge_driver_kind" == fresh ]]; then
        bridge_registered="$(/usr/bin/systemextensionsctl list)" || return 1
        if /usr/bin/grep -Fq "$bridge_driver_identifier" <<< "$bridge_registered"; then
            bridge_driver_run_manager deactivate "$bridge_stage/driver-restore.log" || return 1
        fi
        bridge_driver_absent || return 1
        /bin/rm -rf "$bridge_shared_driver" "$bridge_driver_manager" || return 1
        if [[ -n "$bridge_current" ]]; then /usr/sbin/pkgutil --forget "$bridge_driver_identifier" || return 1; fi
    else return 1
    fi
    bridge_driver_write_phase restored || return 1
    bridge_driver_changed=0
}
