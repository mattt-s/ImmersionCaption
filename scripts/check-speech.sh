#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_path="${1:-$project_root/build/ImmersionCaption.app}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/ImmersionCaption-speech.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# The only audio used is this public synthetic fixture, written to a temporary file.
say -v Tingting -r 190 -o "$check_dir/fixture.aiff" '货船已经到达广州的黄埔港。另一部分继续往北走。'
open -n "$bundle_path" --args --check-speech "$check_dir/fixture.aiff" "$check_dir/report.json"
for ((attempt = 0; attempt < 60; attempt++)); do
    if [[ -f "$check_dir/report.json" ]]; then
        python3 - "$check_dir/report.json" <<'PY'
import json, sys
with open(sys.argv[1]) as report_file:
    report = json.load(report_file)
print(json.dumps(report, indent=2))
sys.exit(0 if report.get('passed') else 1)
PY
        exit $?
    fi
    sleep 1
done
echo 'Speech check timed out waiting for the app metadata report.' >&2
exit 1
