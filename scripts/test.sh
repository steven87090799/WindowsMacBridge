#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
source "$task_root/scripts/build-environment.sh"
# Some CLT toolchains ship Testing.framework but don't discover its macro plugin.
# Resolve the installed plugin without modifying the SDK or downloading dependencies.
task_swift_bin="$(xcrun --find swiftc)"
task_plugin="$(dirname "$(dirname "$task_swift_bin")")/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$task_plugin" ]; then
    swift test --scratch-path "$task_scratch" --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$task_plugin" "$@"
else
    swift test --scratch-path "$task_scratch" --disable-xctest "$@"
fi
