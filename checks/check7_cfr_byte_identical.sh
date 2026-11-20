#!/usr/bin/env bash
# Check 7: CFR output is byte-identical to the pre-fix code.
#
# `checks/baseline/` holds the list-scenes CSV, HTML, and stats CSV produced for
# goldeneye.mp4 (23.976 CFR) and testvideo.mp4 (29.97 CFR) by the baseline commit, on
# both backends. Regenerate those outputs here and require byte equality.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for video in goldeneye testvideo; do
    for backend in pyav opencv; do
        dir="$WORK/${video}_${backend}"
        mkdir -p "$dir"
        python3 -m scenedetect -q -i "tests/resources/$video.mp4" -b "$backend" \
            -o "$dir" -s "$dir/stats.csv" detect-content list-scenes save-html --no-images \
            >/dev/null 2>&1
    done
done

failures=()
for f in $(cd checks/baseline && find . -type f | sort); do
    if ! cmp -s "checks/baseline/$f" "$WORK/$f"; then
        failures+=("$f differs from the baseline")
    fi
done

if [ "${#failures[@]}" -ne 0 ]; then
    printf 'FAIL check7_cfr_byte_identical\n'
    for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
printf 'PASS check7_cfr_byte_identical: CFR 23.976 and 29.97 scene/stats/HTML output is '
printf 'byte-identical to the baseline on both backends\n'
