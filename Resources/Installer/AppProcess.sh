#!/bin/bash
# The GUI and privileged input mode use the same executable. Only a live GUI
# prevents installation; root input mode is stopped via its owned launchd job.
bridge_gui_running() {
    local bridge_pids bridge_query bridge_pid bridge_uid
    if bridge_pids="$(/usr/bin/pgrep -x WindowsMacBridge)"; then :
    else
        bridge_query=$?
        [[ "$bridge_query" == 1 ]] && return 1
        return 2
    fi
    for bridge_pid in $bridge_pids; do
        [[ "$bridge_pid" =~ ^[0-9]+$ ]] || return 2
        bridge_uid="$(/bin/ps -p "$bridge_pid" -o uid=)" || return 2
        [[ "$bridge_uid" =~ ^[[:space:]]*0[[:space:]]*$ ]] || return 0
    done
    return 1
}
