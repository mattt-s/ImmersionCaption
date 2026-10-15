#!/bin/bash
# Launches the local development bundle and checks only its process/window metadata.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_path="$project_root/build/ImmersionCaption.app"
if [[ ! -d "$bundle_path" ]]; then
    echo "Build the application with scripts/build-app.sh first." >&2
    exit 1
fi
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
swiftc "$project_root/scripts/AppLaunchChecks/main.swift" -o "$temporary_dir/check-app-launch"
open -n "$bundle_path"
"$temporary_dir/check-app-launch" "$bundle_path"
