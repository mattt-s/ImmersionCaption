#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
swiftc "$project_root"/Packages/CaptionCore/Sources/CaptionCore/*.swift \
    "$project_root/scripts/PromptProbe/main.swift" -o "$temporary_dir/prompt-probe"
python3 "$project_root/scripts/smoke-translation.py" "$temporary_dir/prompt-probe"
