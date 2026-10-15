#!/bin/bash
set -euo pipefail

compiler_version="$(swiftc --version | head -n 1)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
echo "Compiler: $compiler_version"
echo "SDK: $sdk_path"
if ! [[ "$compiler_version" =~ Swift\ version\ ([0-9]+)\.([0-9]+) ]]; then
    echo "Unable to identify the Swift compiler." >&2
    exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
if (( major < 5 || (major == 5 && minor < 9) )); then
    echo "Swift 5.9+ is required. Finish installing Xcode 15.2+ and select its developer directory." >&2
    exit 1
fi
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
IFS=. read -r sdk_major sdk_minor sdk_patch <<< "$sdk_version"
if (( sdk_major < 14 || (sdk_major == 14 && ${sdk_minor:-0} < 2) )); then
    echo "A macOS 14.2+ SDK with Core Audio process taps is required." >&2
    exit 1
fi
echo "Build prerequisites are available. Runtime permissions and Mandarin assets are checked on Start."
