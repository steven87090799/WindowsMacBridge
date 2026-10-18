#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
source "$task_root/scripts/build-environment.sh"
bash "$task_root/scripts/prepare-hid-backend.sh"
# Some CLT toolchains ship Testing.framework but don't discover its macro plugin.
# Resolve the installed plugin without modifying the SDK or downloading dependencies.
task_swift_bin="$(xcrun --find swiftc)"
task_plugin="$(dirname "$(dirname "$task_swift_bin")")/lib/swift/host/plugins/testing/libTestingMacros.dylib"
task_test=(swift test --jobs "${BRIDGE_BUILD_JOBS:-2}" --scratch-path "$task_scratch" --disable-xctest)
if [ -f "$task_plugin" ]; then
    task_test+=(-Xswiftc -load-plugin-library -Xswiftc "$task_plugin")
fi
# phys_footprint measures the whole process. A serialized suite still overlaps
# unrelated suites, so full runs execute this regression in a separate process.
# Explicit selection, serial runs and caller-owned report output stay one run.
task_isolate_memory=1
for task_arg in "$@"; do
    case "$task_arg" in
        --filter|--filter=*|--skip|--skip=*|-s|--specifier|--specifier=*|--no-parallel|\
        -l|--list-tests|list|last|-h|-help|--help|--version|--debugger|\
        --enable-code-coverage|--xunit-output|--xunit-output=*|\
        --show-codecov-path|--show-code-coverage-path|--show-coverage-path)
            task_isolate_memory=0 ;;
    esac
done
if [ "$task_isolate_memory" == 0 ]; then
    "${task_test[@]}" "$@"
    exit 0
fi
task_memory_test='BridgePlatformTests.ScreenshotBoundedReadTests/repeatedPreparationDoesNotGrowMemoryWithCaptureCount'
"${task_test[@]}" "$@" --skip "$task_memory_test"
task_memory_args=()
task_worker_value=0
task_needs_skip_build=1
for task_arg in "$@"; do
    if [ "$task_worker_value" == 1 ]; then task_worker_value=0; continue; fi
    case "$task_arg" in
        --parallel) ;;
        --num-workers) task_worker_value=1 ;;
        --num-workers=*) ;;
        --skip-build) task_needs_skip_build=0; task_memory_args+=("$task_arg") ;;
        *) task_memory_args+=("$task_arg") ;;
    esac
done
if [ "$task_needs_skip_build" == 1 ]; then task_memory_args+=(--skip-build); fi
"${task_test[@]}" "${task_memory_args[@]}" --no-parallel --filter "$task_memory_test"
