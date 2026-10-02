#!/bin/bash
set -euo pipefail
bridge_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$bridge_root"
task_root="$bridge_root"
source scripts/build-environment.sh
bridge_app="$(cat build/APP_PATH.txt)"
bridge_helper="$(cat build/HID_HELPER_PATH.txt)"
bridge_sdk="$bridge_root/Tools/HIDBackend/SDK"
bridge_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bridge_app/Contents/Info.plist")"
bridge_release="${BRIDGE_RELEASE_VERSION:-$bridge_version-preview.3}"
[[ "$bridge_release" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || exit 1
bridge_stage="$(/usr/bin/mktemp -d "$task_scratch/Artifacts/.single-app.XXXXXX")"
trap '/bin/rm -rf "$bridge_stage"' EXIT
bridge_single_app="$bridge_stage/WindowsMacBridge.app"
/usr/bin/ditto --noextattr --norsrc "$bridge_app" "$bridge_single_app"
bridge_payload="$bridge_single_app/Contents/Resources/BackendPayload"
[[ ! -e "$bridge_payload" ]] || { echo 'Build a fresh App before embedding its payload.' >&2; exit 1; }
/bin/mkdir -p "$bridge_payload/Driver" "$bridge_payload/BridgeHIDHelper.app/Contents/MacOS" "$bridge_payload/Licenses"
/bin/cp "$bridge_helper" "$bridge_payload/BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper"
/bin/cp Resources/Installer/HIDHelper-Info.plist "$bridge_payload/BridgeHIDHelper.app/Contents/Info.plist"
for bridge_key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Set :$bridge_key $(/usr/libexec/PlistBuddy -c "Print :$bridge_key" "$bridge_app/Contents/Info.plist")" \
        "$bridge_payload/BridgeHIDHelper.app/Contents/Info.plist"
done
bridge_rollback_pkg="$HOME/Library/Caches/WindowsMacBridge/DriverRollback/Karabiner-DriverKit-VirtualHIDDevice-7.3.0.pkg"
[[ "$(/usr/bin/shasum -a 256 "$bridge_sdk/dist/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg" | /usr/bin/cut -d ' ' -f 1)" == ff8c7fdc5e25387c7805fc7509a0fa9cf98f69ba582704f717fddcae47424387 ]] || exit 1
[[ "$(/usr/bin/shasum -a 256 "$bridge_rollback_pkg" | /usr/bin/cut -d ' ' -f 1)" == 4ccd9b11628f4c319b17452927827a8313728fe60292e4f789ef4ba626e09ba0 ]] || exit 1
/bin/cp "$bridge_sdk/dist/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg" "$bridge_rollback_pkg" "$bridge_payload/Driver/"
/usr/bin/ditto Resources/Licenses "$bridge_payload/Licenses"
/usr/bin/ditto "$bridge_sdk/include" "$bridge_payload/Licenses/SDKHeaders"
/usr/bin/ditto "$bridge_sdk/vendor/vendor/include" "$bridge_payload/Licenses/VendorHeaders"
for bridge_file in InstallBackend.sh DriverTransaction.sh UninstallBackend.sh local.WindowsMacBridge.HIDHelper.plist local.WindowsMacBridge.VirtualHIDService.plist; do
    /bin/cp "Resources/Installer/$bridge_file" "$bridge_payload/"
done
/usr/bin/clang -target arm64-apple-macos14.0 -O2 -Wall -Wextra -Werror Resources/Installer/DriverProcessRunner.c -o "$bridge_payload/DriverProcessRunner"
/usr/bin/xattr -dr com.apple.FinderInfo "$bridge_single_app" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$bridge_single_app" 2>/dev/null || true
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$bridge_payload/DriverProcessRunner"
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$bridge_payload/BridgeHIDHelper.app"
/usr/bin/codesign --verify --strict "$bridge_payload/BridgeHIDHelper.app"
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime --entitlements Resources/AppEntitlements.plist "$bridge_single_app"
/usr/bin/codesign --verify --deep --strict "$bridge_single_app"
bridge_output="$task_scratch/Artifacts/SingleApp/WindowsMacBridge-$bridge_release"
bridge_zip="$bridge_root/build/download/WindowsMacBridge-$bridge_release-app-macos-arm64.zip"
[[ ! -e "$bridge_output" && ! -e "$bridge_zip" ]] || { echo 'Output exists; use a fresh release version.' >&2; exit 1; }
/bin/mkdir -p "$bridge_output" "$bridge_root/build/download"
/bin/mv "$bridge_single_app" "$bridge_output/WindowsMacBridge.app"
/usr/bin/ditto -c -k --noextattr --norsrc --keepParent "$bridge_output/WindowsMacBridge.app" "$bridge_zip"
printf '%s\n' "$bridge_output/WindowsMacBridge.app" > build/SINGLE_APP_PATH.txt
printf '%s\n' "$bridge_zip" > build/SINGLE_APP_RELEASE_PATH.txt
/usr/bin/shasum -a 256 "$bridge_zip" > "$bridge_zip.sha256"
printf 'Single App: %s\n' "$bridge_zip"
