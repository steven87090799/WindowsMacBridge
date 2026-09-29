#!/bin/bash
set -euo pipefail
bridge_root="$(cd "$(dirname "$0")/.." && pwd)"
bridge_revision=ba98de7fae2d529b9debe82890765dc66246f4ff
bridge_checksum=a682e6a6afa1f06014e8065bde1adf42da1f1eaf81cc9a95943a2337581f667f
bridge_cache="$HOME/Library/Caches/WindowsMacBridge/HIDSDK/$bridge_revision"
bridge_sdk="$bridge_cache/source"
bridge_package="$bridge_root/Tools/HIDBackend"
mkdir -p "$bridge_cache"
if [ ! -f "$bridge_cache/verified" ]; then
    bridge_archive="$bridge_cache/source.tar.gz"
    if [ -n "${WMB_HID_SDK_ARCHIVE:-}" ]; then
        cp "$WMB_HID_SDK_ARCHIVE" "$bridge_archive"
    elif [ ! -f "$bridge_archive" ]; then
        curl --fail --location --proto '=https' --tlsv1.2 \
            "https://api.github.com/repos/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tarball/$bridge_revision" \
            -o "$bridge_archive"
    fi
    bridge_actual="$(shasum -a 256 "$bridge_archive" | cut -d ' ' -f 1)"
    if [ "$bridge_actual" != "$bridge_checksum" ]; then
        echo 'VirtualHID SDK checksum mismatch; nothing was built or installed.' >&2
        exit 1
    fi
    mkdir -p "$bridge_sdk"
    tar -xzf "$bridge_archive" -C "$bridge_sdk" --strip-components=1
    printf '%s\n' "$bridge_checksum" > "$bridge_cache/verified"
fi
if [ ! -e "$bridge_package/SDK" ] && [ ! -L "$bridge_package/SDK" ]; then
    ln -s "$bridge_sdk" "$bridge_package/SDK"
elif [ "$(readlink "$bridge_package/SDK")" != "$bridge_sdk" ]; then
    echo 'Existing SDK path differs; left unchanged.' >&2
    exit 1
fi
bridge_scratch="$bridge_cache/build"
python3 "$bridge_root/scripts/prepare-hid-sdk.py" "$bridge_sdk/include" "$bridge_cache/bounded-include"
if [ ! -e "$bridge_package/SDKOverride" ] && [ ! -L "$bridge_package/SDKOverride" ]; then
    ln -s "$bridge_cache/bounded-include" "$bridge_package/SDKOverride"
elif [ "$(readlink "$bridge_package/SDKOverride")" != "$bridge_cache/bounded-include" ]; then
    echo 'Existing SDKOverride differs; left unchanged.' >&2; exit 1
fi
swift build --package-path "$bridge_package" --scratch-path "$bridge_scratch" -c release
bridge_swift="$(xcrun --find swiftc)"
bridge_plugin="$(dirname "$(dirname "$bridge_swift")")/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$bridge_plugin" ]; then
    swift test --package-path "$bridge_package" --scratch-path "$bridge_scratch" --disable-xctest \
        -Xswiftc -load-plugin-library -Xswiftc "$bridge_plugin"
else
    swift test --package-path "$bridge_package" --scratch-path "$bridge_scratch" --disable-xctest
fi
bridge_bin="$(swift build --package-path "$bridge_package" --scratch-path "$bridge_scratch" -c release --show-bin-path)/BridgeHIDHelper"
"$bridge_bin" --self-check
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --identifier local.WindowsMacBridge.HIDHelper --options runtime "$bridge_bin"
/usr/bin/codesign --verify --strict "$bridge_bin"
mkdir -p "$bridge_root/build"
printf '%s\n' "$bridge_bin" > "$bridge_root/build/HID_HELPER_PATH.txt"
printf 'Helper built (not installed): %s\n' "$bridge_bin"
