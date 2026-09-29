#!/bin/bash
# User-space installation: drag the App into Applications. No installer or driver.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
source "$task_root/scripts/build-environment.sh"
[[ -f build/APP_PATH.txt ]] || { echo 'Build the App first.' >&2; exit 1; }
bridge_app="$(cat build/APP_PATH.txt)"
codesign --verify --strict "$bridge_app"
bridge_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bridge_app/Contents/Info.plist")"
bridge_release="${BRIDGE_RELEASE_VERSION:-$bridge_version-preview.1}"
[[ "$bridge_release" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
bridge_name="WindowsMacBridge-$bridge_release-macos-arm64"
bridge_output="$task_root/build/download/$bridge_name.dmg"
[[ ! -e "$bridge_output" && ! -e "$bridge_output.sha256" ]] || { echo 'DMG output exists; left unchanged.' >&2; exit 1; }
bridge_stage="$(mktemp -d "$task_scratch/drag-install.XXXXXX")"
trap 'rm -rf "$bridge_stage"' EXIT
mkdir -p "$bridge_stage/Volume" "$task_root/build/download"
ditto --noextattr --norsrc "$bridge_app" "$bridge_stage/Volume/WindowsMacBridge.app"
ln -s /Applications "$bridge_stage/Volume/Applications"
cp Resources/DragInstall.txt "$bridge_stage/Volume/開始使用.txt"
codesign --verify --strict "$bridge_stage/Volume/WindowsMacBridge.app"
hdiutil create -quiet -volname WindowsMacBridge -srcfolder "$bridge_stage/Volume" \
    -format UDZO "$bridge_stage/$bridge_name.dmg"
hdiutil verify -quiet "$bridge_stage/$bridge_name.dmg"
cp "$bridge_stage/$bridge_name.dmg" "$bridge_output"
(cd "$(dirname "$bridge_output")" && shasum -a 256 "$(basename "$bridge_output")") > "$bridge_output.sha256"
printf '%s\n' "$bridge_output" > build/DMG_PATH.txt
printf 'Packaged drag-install App (not installed): %s\n' "$bridge_output"
