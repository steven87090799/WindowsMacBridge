#!/bin/bash
set -euo pipefail
bridge_root="$(cd "$(dirname "$0")/.." && pwd)"
bridge_revision=ba98de7fae2d529b9debe82890765dc66246f4ff
bridge_checksum=a682e6a6afa1f06014e8065bde1adf42da1f1eaf81cc9a95943a2337581f667f
bridge_cache="$HOME/Library/Caches/WindowsMacBridge/HIDSDK/$bridge_revision"
bridge_sdk="$bridge_cache/source"
bridge_package="$bridge_root/Tools/HIDBackend"
mkdir -p "$bridge_cache"
bridge_archive="$bridge_cache/source.tar.gz"
if [ -n "${WMB_HID_SDK_ARCHIVE:-}" ]; then
    if [[ "$WMB_HID_SDK_ARCHIVE" != "$bridge_archive" ]]; then cp "$WMB_HID_SDK_ARCHIVE" "$bridge_archive"; fi
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
# Reconstruct from verified bytes; a stale marker or edited cache cannot become build input.
bridge_sdk_stage="$(mktemp -d "$bridge_cache/.source-stage.XXXXXX")"
trap 'rm -rf "$bridge_sdk_stage"' EXIT
tar -xzf "$bridge_archive" -C "$bridge_sdk_stage" --strip-components=1
if [[ -d "$bridge_sdk" ]]; then mv "$bridge_sdk" "$bridge_sdk_stage/old-source"; fi
mkdir -p "$bridge_sdk"
# ditto preserves archive structure while SDK always points to the same stable directory.
/usr/bin/ditto "$bridge_sdk_stage/include" "$bridge_sdk/include"
/usr/bin/ditto "$bridge_sdk_stage/dist" "$bridge_sdk/dist"
/usr/bin/ditto "$bridge_sdk_stage/vendor/vendor/include" "$bridge_sdk/vendor/vendor/include"
cp "$bridge_sdk_stage/LICENSE.md" "$bridge_sdk/LICENSE.md"
rm -rf "$bridge_cache/bounded-include"
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
