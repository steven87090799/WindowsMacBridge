#!/bin/bash
set -euo pipefail
bridge_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$bridge_root"
[[ -f build/APP_PATH.txt && -f build/HID_HELPER_PATH.txt ]] || { echo 'Build App/helper first.' >&2; exit 1; }
bridge_app="$(cat build/APP_PATH.txt)"
bridge_helper="$(cat build/HID_HELPER_PATH.txt)"
bridge_sdk="$bridge_root/Tools/HIDBackend/SDK"
task_root="$bridge_root"
source "$bridge_root/scripts/build-environment.sh"
# Signed bundles stay outside file-provider/synced folders which may reattach FinderInfo.
bridge_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bridge_app/Contents/Info.plist")"
bridge_release="${BRIDGE_RELEASE_VERSION:-$bridge_version-preview.1}"
[[ "$bridge_release" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
bridge_output="$task_scratch/Artifacts/Packages/WindowsMacBridge-$bridge_release-macos-arm64"
[[ ! -e "$bridge_output" ]] || { echo 'Package output exists; use a fresh version/path.' >&2; exit 1; }
mkdir -p "$bridge_output/Driver" "$bridge_output/BridgeHIDHelper.app/Contents/MacOS" "$bridge_output/Licenses"
ditto --noextattr --norsrc "$bridge_app" "$bridge_output/WindowsMacBridge.app"
cp "$bridge_helper" "$bridge_output/BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper"
cp Resources/Installer/HIDHelper-Info.plist "$bridge_output/BridgeHIDHelper.app/Contents/Info.plist"
for bridge_key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Set :$bridge_key $(/usr/libexec/PlistBuddy -c "Print :$bridge_key" "$bridge_app/Contents/Info.plist")" \
        "$bridge_output/BridgeHIDHelper.app/Contents/Info.plist"
done
cp Resources/UserGuide.md "$bridge_output/UserGuide.md"
cp Resources/TwoMacAcceptance.md "$bridge_output/TwoMacAcceptance.md"
ditto Resources/Licenses "$bridge_output/Licenses"
# Keep SDK/vendor header copyright and license notices with distributed binaries.
ditto "$bridge_sdk/include" "$bridge_output/Licenses/SDKHeaders"
ditto "$bridge_sdk/vendor/vendor/include" "$bridge_output/Licenses/VendorHeaders"
cp "$bridge_sdk/dist/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg" "$bridge_output/Driver/"
# A known ABI upgrade must carry a verified reinstallable rollback package.
# Fetch during unprivileged packaging, never during an administrator transaction.
bridge_rollback_cache="$HOME/Library/Caches/WindowsMacBridge/DriverRollback"
bridge_rollback_pkg="$bridge_rollback_cache/Karabiner-DriverKit-VirtualHIDDevice-7.3.0.pkg"
mkdir -p "$bridge_rollback_cache"
if [[ ! -f "$bridge_rollback_pkg" ]]; then
    bridge_rollback_download="$(mktemp "$bridge_rollback_cache/.download.XXXXXX")"
    if ! curl --fail --location --proto '=https' --tlsv1.2 --max-time 120 \
        https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v7.3.0/Karabiner-DriverKit-VirtualHIDDevice-7.3.0.pkg \
        -o "$bridge_rollback_download"; then rm -f "$bridge_rollback_download"; exit 1; fi
    if [[ "$(shasum -a 256 "$bridge_rollback_download" | cut -d ' ' -f 1)" != 4ccd9b11628f4c319b17452927827a8313728fe60292e4f789ef4ba626e09ba0 ]]; then
        rm -f "$bridge_rollback_download"; echo 'Rollback package checksum mismatch.' >&2; exit 1
    fi
    mv "$bridge_rollback_download" "$bridge_rollback_pkg"
fi
[[ "$(shasum -a 256 "$bridge_rollback_pkg" | cut -d ' ' -f 1)" == 4ccd9b11628f4c319b17452927827a8313728fe60292e4f789ef4ba626e09ba0 ]] || exit 1
/usr/sbin/pkgutil --check-signature "$bridge_rollback_pkg"
cp "$bridge_rollback_pkg" "$bridge_output/Driver/"
/usr/bin/clang -target arm64-apple-macos14.0 -O2 -Wall -Wextra -Werror Resources/Installer/DriverProcessRunner.c -o "$bridge_output/DriverProcessRunner"
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$bridge_output/DriverProcessRunner"
/usr/bin/codesign --verify --strict "$bridge_output/DriverProcessRunner"
for bridge_file in Install.command ActivateDriver.command Stop.command Uninstall.command \
    InstallBackend.sh DriverTransaction.sh UninstallBackend.sh local.WindowsMacBridge.HIDHelper.plist \
    local.WindowsMacBridge.VirtualHIDService.plist READ-ME-FIRST.md; do
    cp "Resources/Installer/$bridge_file" "$bridge_output/"
done
for bridge_file in Install.command ActivateDriver.command Stop.command Uninstall.command InstallBackend.sh UninstallBackend.sh; do
    chmod +x "$bridge_output/$bridge_file"
done
xattr -dr com.apple.FinderInfo "$bridge_output" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$bridge_output" 2>/dev/null || true
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$bridge_output/BridgeHIDHelper.app"
codesign --verify --strict "$bridge_output/BridgeHIDHelper.app"
codesign --verify --strict "$bridge_output/WindowsMacBridge.app"
"$bridge_output/BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper" --self-check
"$bridge_output/BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper" --controller-pin "$bridge_output/WindowsMacBridge.app" > "$bridge_output/CONTROLLER-PIN.plist"
python3 - "$bridge_output" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
paths = sorted(p for p in root.rglob('*') if p.is_file())
with (root/'PAYLOAD-SHA256SUMS').open('w') as output:
    for path in paths:
        output.write(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path.relative_to(root)) + '\n')
PY
(cd "$bridge_output" && shasum -a 256 -c PAYLOAD-SHA256SUMS > /dev/null)
ditto -c -k --noextattr --norsrc --keepParent "$bridge_output" "$bridge_output.zip"
mkdir -p "$bridge_root/build/download"
bridge_zip="$bridge_root/build/download/$(basename "$bridge_output").zip"
[[ ! -e "$bridge_zip" ]] || { echo 'Release ZIP exists; left unchanged.' >&2; exit 1; }
cp "$bridge_output.zip" "$bridge_zip"
(cd "$(dirname "$bridge_zip")" && shasum -a 256 "$(basename "$bridge_zip")") > "$bridge_zip.sha256"
printf '%s\n' "$bridge_zip" > build/RELEASE_PATH.txt
printf 'Packaged (not installed): %s\n' "$bridge_zip"
