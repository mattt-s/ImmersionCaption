#!/bin/bash
# Build native development installers without changing the installed application.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
"$project_root/scripts/build-app.sh"

bundle_path="$project_root/build/ImmersionCaption.app"
plist_buddy=/usr/libexec/PlistBuddy
version="$("$plist_buddy" -c 'Print :CFBundleShortVersionString' "$bundle_path/Contents/Info.plist")"
minimum_os="$("$plist_buddy" -c 'Print :LSMinimumSystemVersion' "$bundle_path/Contents/Info.plist")"
architectures="$(lipo -archs "$bundle_path/Contents/MacOS/ImmersionCaption")"
case "$architectures" in
    arm64|x86_64) architecture_label="$architectures" ;;
    'arm64 x86_64'|'x86_64 arm64') architecture_label=universal ;;
    *) echo "Unsupported package architectures: $architectures" >&2; exit 1 ;;
esac
package_name="ImmersionCaption-$version-$architecture_label"
staging_dir="$(mktemp -d "$project_root/build/.ImmersionCaption-package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

# Only the application is included. No user preferences, models, logs, or install scripts.
payload_root="$staging_dir/payload"
mkdir -p "$payload_root/Applications"
ditto "$bundle_path" "$payload_root/Applications/ImmersionCaption.app"
components="$staging_dir/components.plist"
pkgbuild --analyze --root "$payload_root" "$components"
# Newer pkgbuild omits its false default; make it explicit across toolchain versions.
"$plist_buddy" -c 'Delete :0:BundleIsRelocatable' "$components" >/dev/null 2>&1 || true
"$plist_buddy" -c 'Add :0:BundleIsRelocatable bool false' \
    -c 'Set :0:BundleIsVersionChecked true' \
    -c 'Set :0:BundleHasStrictIdentifier true' \
    -c 'Set :0:BundleOverwriteAction upgrade' "$components"
pkgbuild --root "$payload_root" --component-plist "$components" \
    --identifier app.ImmersionCaption.installer --version "$version" \
    --install-location / --ownership recommended "$staging_dir/ImmersionCaption-component.pkg"

# Synthesize native Installer checks from the actual app's architecture and OS requirement.
requirements="$staging_dir/requirements.plist"
"$plist_buddy" -c 'Add :arch array' -c 'Add :os array' \
    -c "Add :os:0 string $minimum_os" -c 'Add :home bool false' "$requirements"
read -r -a architecture_list <<< "$architectures"
index=0
for architecture in "${architecture_list[@]}"; do
    "$plist_buddy" -c "Add :arch:$index string $architecture" "$requirements"
    index=$((index + 1))
done
productbuild --synthesize --product "$requirements" \
    --package "$staging_dir/ImmersionCaption-component.pkg" "$staging_dir/Distribution.xml"
installer_options=(--distribution "$staging_dir/Distribution.xml" --package-path "$staging_dir")
if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
    installer_options+=(--sign "$INSTALLER_SIGN_IDENTITY")
fi
productbuild "${installer_options[@]}" "$staging_dir/$package_name.pkg"

# A drag-and-drop installation option: copy the app via the Applications link.
dmg_root="$staging_dir/disk-image"
mkdir -p "$dmg_root"
ditto "$bundle_path" "$dmg_root/ImmersionCaption.app"
ln -s /Applications "$dmg_root/Applications"
cat > "$dmg_root/INSTALL.txt" <<'INSTALL'
ImmersionCaption

Quit older copies, drag ImmersionCaption.app to Applications, then launch it there.
Requires macOS 14.2+ and a Mac matching the architecture in the image filename.
Choose the spoken language and allow Speech Recognition and System Audio Recording.
Install the required on-device language resources through macOS before offline use.
This development build is not notarized. No Ollama or external runtime is required.

请先退出旧版本，将 ImmersionCaption.app 拖入 Applications，再从「应用程序」打开。
需要 macOS 14.2 或更高版本，以及与文件名所示架构一致的 Mac。
选择语音语言，并允许「语音识别」和「系统音频录制」权限。
离线使用前，请通过 macOS 安装所需的设备端语言资源。
当前为未经公证的开发版，无需 Ollama 或外部推理运行时。
INSTALL
hdiutil create -volname ImmersionCaption -srcfolder "$dmg_root" \
    -fs HFS+ -format UDZO "$staging_dir/$package_name.dmg"
hdiutil verify "$staging_dir/$package_name.dmg"

# Publish only completed artifacts. Previous packages survive a failed build.
mv -f "$staging_dir/$package_name.pkg" "$project_root/build/$package_name.pkg"
mv -f "$staging_dir/$package_name.dmg" "$project_root/build/$package_name.dmg"
(
    cd "$project_root/build"
    shasum -a 256 "$package_name.pkg" "$package_name.dmg" > "$package_name.sha256"
)
echo "Installer: $project_root/build/$package_name.pkg"
echo "Disk image: $project_root/build/$package_name.dmg"
echo "Checksums: $project_root/build/$package_name.sha256"
