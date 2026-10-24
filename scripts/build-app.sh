#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
source "$task_root/scripts/build-environment.sh"
bash "$task_root/scripts/prepare-hid-backend.sh"
configuration="${CONFIGURATION:-release}"
bridge_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
bridge_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
[[ "$bridge_sdk_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || exit 1
# Swift 6.4 can stamp the deployment target as the linked SDK even when -sdk
# points at SDK 27. Keep macOS 14 support, but record the actual selected SDK so
# linked-on-or-after system appearance decisions see the current generation.
bridge_sdk_link=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$bridge_sdk_version")
swift build --scratch-path "$task_scratch" --sdk "$bridge_sdk_path" -c "$configuration" --product WindowsMacBridge --jobs "${BRIDGE_BUILD_JOBS:-2}" "${bridge_sdk_link[@]}"
binary_directory="$(swift build --scratch-path "$task_scratch" -c "$configuration" --show-bin-path)"
bridge_ocr_feature="$("$binary_directory/WindowsMacBridge" --print-ocr-feature)"
[[ "$bridge_ocr_feature" == enabled || "$bridge_ocr_feature" == disabled ]] || exit 1
if [[ "$bridge_ocr_feature" == enabled ]]; then
    swift build --scratch-path "$task_scratch" --sdk "$bridge_sdk_path" -c "$configuration" --product WindowsMacBridgeTextWorker --jobs "${BRIDGE_BUILD_JOBS:-2}" "${bridge_sdk_link[@]}"
fi
mkdir -p "$task_scratch/Artifacts"
bridge_stage="$(mktemp -d "$task_scratch/Artifacts/.app-stage.XXXXXX")"
trap 'rm -rf "$bridge_stage"' EXIT
app_directory="$bridge_stage/WindowsMacBridge.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/WindowsMacBridge" "$app_directory/Contents/MacOS/WindowsMacBridge"
mkdir -p "$app_directory/Contents/Helpers"
clang -target arm64-apple-macos14.0 -isysroot "$bridge_sdk_path" "${bridge_sdk_link[@]}" \
    -std=c11 -O2 -Wall -Wextra -Werror -framework CoreFoundation \
    "$task_root/Tools/RecoveryHelper/RecoveryHelper.c" \
    -o "$app_directory/Contents/Helpers/WindowsMacBridgeRecovery"
if [[ "$bridge_ocr_feature" == enabled ]]; then
    mkdir -p "$app_directory/Contents/Helpers"
    cp "$binary_directory/WindowsMacBridgeTextWorker" "$app_directory/Contents/Helpers/WindowsMacBridgeTextWorker"
fi
cp "$task_root/Resources/Info.plist" "$app_directory/Contents/Info.plist"
source "$task_root/scripts/source-version.sh"
bridge_build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/libexec/PlistBuddy -c "Add :WMBGitRevision string $bridge_revision" "$app_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :WMBBuildDateUTC string $bridge_build_date" "$app_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :WMBSourceState string $bridge_source_state" "$app_directory/Contents/Info.plist"
for brand_asset in AppIcon.icns MenuBarIcon.png MenuBarPausedIcon.png; do
    cp "$task_root/Resources/Brand/$brand_asset" "$app_directory/Contents/Resources/$brand_asset"
done
cp "$task_root/Resources/UserGuide.md" "$app_directory/Contents/Resources/UserGuide.md"
cp "$task_root/Resources/AcceptanceGuide.md" "$app_directory/Contents/Resources/AcceptanceGuide.md"
cp "$task_root/Resources/TwoMacAcceptance.md" "$app_directory/Contents/Resources/TwoMacAcceptance.md"
cp "$task_root/Resources/Installer/LaunchEmbeddedInstall.sh" "$app_directory/Contents/Resources/LaunchEmbeddedInstall.sh"
cp "$task_root/Resources/Installer/LaunchEmbeddedUninstall.sh" "$app_directory/Contents/Resources/LaunchEmbeddedUninstall.sh"
cp "$task_root/Resources/Installer/AppProcess.sh" "$app_directory/Contents/Resources/AppProcess.sh"
cp "$task_root/Resources/Installer/RelaunchApp.sh" "$app_directory/Contents/Resources/RelaunchApp.sh"
/usr/bin/ditto "$task_root/Resources/Licenses" "$app_directory/Contents/Resources/Licenses"
# The App adapter explicitly loads from Contents/Resources; no build-path fallback.
resource_bundle="$binary_directory/WindowsMacBridge_BridgePlatform.bundle"
[[ -d "$resource_bundle" ]] || { echo 'Required BridgePlatform resource bundle missing.' >&2; exit 1; }
/usr/bin/ditto "$resource_bundle" "$app_directory/Contents/Resources/WindowsMacBridge_BridgePlatform.bundle"
extension_directory="$app_directory/Contents/PlugIns/WindowsMacBridgeFinderSync.appex"
mkdir -p "$extension_directory/Contents/MacOS"
cp "$task_root/Extensions/FinderSync/Info.plist" "$extension_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_directory/Contents/Info.plist")" "$extension_directory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_directory/Contents/Info.plist")" "$extension_directory/Contents/Info.plist"
bridge_optimization=-Onone
if [[ "$configuration" == release ]]; then bridge_optimization="${FINDER_RELEASE_OPTIMIZATION:--O}"; fi
[[ "$bridge_optimization" == -Onone || "$bridge_optimization" == -O || "$bridge_optimization" == -Osize ]] || exit 1
swiftc "$bridge_optimization" -emit-executable -parse-as-library -module-name WindowsMacBridgeFinderSync \
    -target arm64-apple-macos14.0 -sdk "$bridge_sdk_path" "${bridge_sdk_link[@]}" -framework FinderSync -framework AppKit \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$task_root/Sources/BridgeCore/FinderPathSelection.swift" \
    "$task_root/Sources/BridgeCore/FinderModeSignal.swift" \
    "$task_root/Extensions/FinderSync/FinderSync.swift" \
    -o "$extension_directory/Contents/MacOS/WindowsMacBridgeFinderSync"
bridge_sdk_binaries=("$app_directory/Contents/MacOS/WindowsMacBridge" "$extension_directory/Contents/MacOS/WindowsMacBridgeFinderSync")
bridge_sdk_binaries+=("$app_directory/Contents/Helpers/WindowsMacBridgeRecovery")
if [[ "$bridge_ocr_feature" == enabled ]]; then bridge_sdk_binaries+=("$app_directory/Contents/Helpers/WindowsMacBridgeTextWorker"); fi
python3 "$task_root/scripts/verify-build-sdk.py" "$bridge_sdk_version" "${bridge_sdk_binaries[@]}"
# File providers can attach FinderInfo to generated bundles; codesign rejects it.
# Only generated app metadata is affected, never source files or user documents.
/usr/bin/xattr -dr com.apple.FinderInfo "$app_directory" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$app_directory" 2>/dev/null || true
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$app_directory/Contents/Helpers/WindowsMacBridgeRecovery"
if [[ "$bridge_ocr_feature" == enabled ]]; then
    /usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime "$app_directory/Contents/Helpers/WindowsMacBridgeTextWorker"
fi
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime \
    --entitlements "$task_root/Extensions/FinderSync/Entitlements.plist" "$extension_directory"
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime \
    --entitlements "$task_root/Resources/AppEntitlements.plist" "$app_directory"
/usr/bin/codesign --verify --strict "$app_directory"
if [[ "$bridge_ocr_feature" == enabled ]]; then "$app_directory/Contents/Helpers/WindowsMacBridgeTextWorker" --self-check; fi
"$app_directory/Contents/Helpers/WindowsMacBridgeRecovery" --self-check
"$app_directory/Contents/MacOS/WindowsMacBridge" --self-check
"$app_directory/Contents/MacOS/WindowsMacBridge" --resource-self-check > "$bridge_stage/resource-check.json"
python3 - "$bridge_stage/resource-check.json" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    report = json.load(source)
if report.get('loaded_ocr_frameworks') != []:
    raise SystemExit('GUI must not load OCR frameworks; App packaging stopped.')
print('GUI OCR frameworks: none')
PY
bridge_final="$task_scratch/Artifacts/WindowsMacBridge.app"
bridge_previous="$task_scratch/Artifacts/.WindowsMacBridge-previous-$$.app"
if [[ -e "$bridge_final" ]]; then mv "$bridge_final" "$bridge_previous"; fi
if ! mv "$app_directory" "$bridge_final"; then
    if [[ -e "$bridge_previous" ]]; then mv "$bridge_previous" "$bridge_final"; fi
    exit 1
fi
rm -rf "$bridge_previous"
app_directory="$bridge_final"
mkdir -p "$task_root/build"
printf '%s\n' "$app_directory" > "$task_root/build/APP_PATH.txt"
printf '%s\n' "$app_directory"
