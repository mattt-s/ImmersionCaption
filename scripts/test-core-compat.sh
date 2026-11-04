#!/bin/bash
# Lightweight domain checks for machines whose command-line tools lack XCTest.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
swiftc "$project_root"/Packages/CaptionCore/Sources/CaptionCore/*.swift \
    "$project_root/scripts/CoreChecks/main.swift" -o "$temporary_dir/core-checks"
"$temporary_dir/core-checks"
