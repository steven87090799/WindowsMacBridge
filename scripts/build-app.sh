#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
source "$task_root/scripts/build-environment.sh"
configuration="${CONFIGURATION:-release}"
swift build --scratch-path "$task_scratch" -c "$configuration" --product WindowsMacBridge
binary_directory="$(swift build --scratch-path "$task_scratch" -c "$configuration" --show-bin-path)"
app_directory="$task_scratch/Artifacts/WindowsMacBridge.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/WindowsMacBridge" "$app_directory/Contents/MacOS/WindowsMacBridge"
cp "$task_root/Resources/Info.plist" "$app_directory/Contents/Info.plist"
for brand_asset in AppIcon.icns MenuBarIcon.png MenuBarPausedIcon.png; do
    cp "$task_root/Resources/Brand/$brand_asset" "$app_directory/Contents/Resources/$brand_asset"
done
cp "$task_root/Resources/UserGuide.md" "$app_directory/Contents/Resources/UserGuide.md"
cp "$task_root/Resources/AcceptanceGuide.md" "$app_directory/Contents/Resources/AcceptanceGuide.md"
/usr/bin/ditto "$task_root/Resources/Licenses" "$app_directory/Contents/Resources/Licenses"
# The App adapter explicitly loads from Contents/Resources; no build-path fallback.
for resource_bundle in "$binary_directory"/*.bundle; do
    [ -d "$resource_bundle" ] || continue
    /usr/bin/ditto "$resource_bundle" "$app_directory/Contents/Resources/$(basename "$resource_bundle")"
done
# File providers can attach FinderInfo to generated bundles; codesign rejects it.
# Only generated app metadata is affected, never source files or user documents.
/usr/bin/xattr -dr com.apple.FinderInfo "$app_directory" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$app_directory" 2>/dev/null || true
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$app_directory"
/usr/bin/codesign --verify --strict "$app_directory"
mkdir -p "$task_root/build"
printf '%s\n' "$app_directory" > "$task_root/build/APP_PATH.txt"
"$app_directory/Contents/MacOS/WindowsMacBridge" --self-check
printf '%s\n' "$app_directory"
