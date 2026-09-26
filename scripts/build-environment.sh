# Sourced by build-app.sh/test.sh. Keep signed intermediates outside synced Documents.
task_hash="$(printf '%s' "$task_root" | shasum -a 256 | cut -c 1-12)"
task_scratch="${BRIDGE_BUILD_DIR:-$HOME/Library/Caches/WindowsMacBridge/$task_hash}"
mkdir -p "$task_scratch"
