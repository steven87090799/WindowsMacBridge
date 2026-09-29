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
bridge_revision="$(git -C "$task_root" rev-parse HEAD)"
bridge_source_state=clean
if [ -n "$(git -C "$task_root" status --porcelain --untracked-files=normal)" ]; then
    bridge_source_state=modified
fi
bridge_build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/libexec/PlistBuddy -c "Add :WMBGitRevision string $bridge_revision" "$app_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :WMBBuildDateUTC string $bridge_build_date" "$app_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :WMBSourceState string $bridge_source_state" "$app_directory/Contents/Info.plist"
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
extension_directory="$app_directory/Contents/PlugIns/WindowsMacBridgeFinderSync.appex"
mkdir -p "$extension_directory/Contents/MacOS"
cp "$task_root/Extensions/FinderSync/Info.plist" "$extension_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_directory/Contents/Info.plist")" "$extension_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_directory/Contents/Info.plist")" "$extension_directory/Contents/Info.plist"
swiftc -emit-executable -parse-as-library -module-name WindowsMacBridgeFinderSync \
    -target arm64-apple-macos14.0 -framework FinderSync -framework AppKit \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$task_root/Sources/BridgeCore/FinderPathSelection.swift" \
    "$task_root/Extensions/FinderSync/FinderSync.swift" \
    -o "$extension_directory/Contents/MacOS/WindowsMacBridgeFinderSync"
# File providers can attach FinderInfo to generated bundles; codesign rejects it.
# Only generated app metadata is affected, never source files or user documents.
/usr/bin/xattr -dr com.apple.FinderInfo "$app_directory" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$app_directory" 2>/dev/null || true
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime \
    --entitlements "$task_root/Extensions/FinderSync/Entitlements.plist" "$extension_directory"
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime \
    --entitlements "$task_root/Resources/AppEntitlements.plist" "$app_directory"
/usr/bin/codesign --verify --strict "$app_directory"
mkdir -p "$task_root/build"
printf '%s\n' "$app_directory" > "$task_root/build/APP_PATH.txt"
"$app_directory/Contents/MacOS/WindowsMacBridge" --self-check
printf '%s\n' "$app_directory"
