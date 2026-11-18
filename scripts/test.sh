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
# Memory regressions measure the entire process. HID ownership tests exercise
# real XPC deadlines on the MainActor. Suite serialization still allows overlap
# with unrelated suites, so each group gets a separate test process.
# Explicit selection, serial runs and caller-owned report output stay one run.
task_isolate_suites=1
for task_arg in "$@"; do
    case "$task_arg" in
        --filter|--filter=*|--skip|--skip=*|-s|--specifier|--specifier=*|--no-parallel|\
        -l|--list-tests|list|last|-h|-help|--help|--version|--debugger|\
        --enable-code-coverage|--xunit-output|--xunit-output=*|\
        --show-codecov-path|--show-code-coverage-path|--show-coverage-path)
            task_isolate_suites=0 ;;
    esac
done
if [ "$task_isolate_suites" == 0 ]; then
    "${task_test[@]}" "$@"
    exit 0
fi
task_memory_tests='BridgePlatformTests\.(ScreenshotBoundedReadTests/repeatedPreparationDoesNotGrowMemoryWithCaptureCount|InputDiagnosticsTests/repeatedTraceSnapshotsKeepMemoryBounded)'
task_hid_tests='BridgePlatformTests\.(HIDReleaseStateMachineTests|BackendOwnershipTests)/'
"${task_test[@]}" "$@" --skip "($task_memory_tests|$task_hid_tests)"
task_serial_args=()
task_worker_value=0
task_needs_skip_build=1
for task_arg in "$@"; do
    if [ "$task_worker_value" == 1 ]; then task_worker_value=0; continue; fi
    case "$task_arg" in
        --parallel) ;;
        --num-workers) task_worker_value=1 ;;
        --num-workers=*) ;;
        --skip-build) task_needs_skip_build=0; task_serial_args+=("$task_arg") ;;
        *) task_serial_args+=("$task_arg") ;;
    esac
done
if [ "$task_needs_skip_build" == 1 ]; then task_serial_args+=(--skip-build); fi
for task_filter in "$task_memory_tests" "$task_hid_tests"; do
    "${task_test[@]}" "${task_serial_args[@]}" --no-parallel --filter "$task_filter"
done
