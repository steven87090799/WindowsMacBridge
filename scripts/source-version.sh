# Sourced by build-app.sh; archive builds must not inherit a parent repository's identity.
bridge_revision=archive
bridge_source_state=archive
if [[ -n "${SOURCE_REVISION:-}" ]]; then
    [[ "$SOURCE_REVISION" =~ ^[[:xdigit:]]{7,64}$ ]] || { echo 'Invalid SOURCE_REVISION.' >&2; return 1; }
    bridge_revision="$SOURCE_REVISION"
    bridge_source_state=provided
elif [[ -e "$task_root/.git" ]] && bridge_revision="$(git -C "$task_root" rev-parse HEAD 2>/dev/null)"; then
    bridge_source_state=clean
    if [[ -n "$(git -C "$task_root" status --porcelain --untracked-files=normal)" ]]; then bridge_source_state=modified; fi
else
    bridge_revision=archive
fi
