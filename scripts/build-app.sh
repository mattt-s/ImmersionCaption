#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
"$project_root/scripts/check-environment.sh"
swift build --configuration release
binary_path="$(swift build --configuration release --show-bin-path)/ImmersionCaption"
bundle_path="$project_root/build/ImmersionCaption.app"
mkdir -p "$project_root/build"
staging_dir="$(mktemp -d "$project_root/build/.ImmersionCaption-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_bundle="$staging_dir/ImmersionCaption.app"
# Keep the previous bundle intact until icon generation and signing both succeed.
mkdir -p "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp "$binary_path" "$staged_bundle/Contents/MacOS/ImmersionCaption"
cp Resources/Info.plist "$staged_bundle/Contents/Info.plist"
"$project_root/scripts/build-icon.sh" "$staged_bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" \
    --entitlements Resources/ImmersionCaption.entitlements \
    --identifier app.ImmersionCaption "$staged_bundle"
codesign --verify --strict "$staged_bundle"
if [[ -d "$bundle_path" ]]; then
    mv "$bundle_path" "$staging_dir/Previous.app"
fi
if ! mv "$staged_bundle" "$bundle_path"; then
    if [[ -d "$staging_dir/Previous.app" ]]; then
        mv "$staging_dir/Previous.app" "$bundle_path"
    fi
    exit 1
fi
echo "Built: $bundle_path"
echo "Launch with: open '$bundle_path'"
