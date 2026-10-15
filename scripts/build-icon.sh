#!/bin/bash
# Converts the generated master artwork into all native macOS icon representations.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_image="$project_root/Resources/Artwork/AppIcon.png"
destination="${1:-$project_root/build/AppIcon.icns}"
width="$(sips -g pixelWidth "$source_image" | awk '/pixelWidth:/ {print $2}')"
height="$(sips -g pixelHeight "$source_image" | awk '/pixelHeight:/ {print $2}')"
if [[ "$width" != "$height" ]] || (( width < 1024 )); then
    echo "AppIcon.png must be square and at least 1024 pixels wide." >&2
    exit 1
fi
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
iconset="$temporary_dir/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$destination")"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_image" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$source_image" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$destination"
echo "Built icon: $destination"
