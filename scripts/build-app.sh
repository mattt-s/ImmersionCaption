#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
"$project_root/scripts/check-environment.sh"
swift build --configuration release
binary_path="$(swift build --configuration release --show-bin-path)/ImmersionCaption"
bundle_path="$project_root/build/ImmersionCaption.app"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources"
cp "$binary_path" "$bundle_path/Contents/MacOS/ImmersionCaption"
cp Resources/Info.plist "$bundle_path/Contents/Info.plist"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" \
    --entitlements Resources/ImmersionCaption.entitlements \
    --identifier app.ImmersionCaption "$bundle_path"
codesign --verify --strict "$bundle_path"
echo "Built: $bundle_path"
echo "Launch with: open '$bundle_path'"
