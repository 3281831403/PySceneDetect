#!/usr/bin/env bash
# Check 6: no ghost scenes.
#
# A short run near the end of the video (`-s 1979`) must produce exactly one scene
# (1979 -> 1980) on both backends, and a full pass must yield contiguous scenes whose
# frame numbers stay within the 1..1980 range. Before the fix, PTS-derived frame
# numbers near the end of the VFR file produced several phantom scenes.
set -euo pipefail
cd "$(dirname "$0")/.."

run() {  # run <backend> <extra args...>
    local backend="$1"; shift
    python3 -m scenedetect -i tests/resources/goldeneye-vfr.mp4 -b "$backend" \
        "time" "$@" detect-content list-scenes 2>&1
}

failures=()
for backend in pyav opencv; do
    out=$(run "$backend" -s 1979)
    rows=$(printf '%s\n' "$out" | grep -c '^ |')
    if printf '%s\n' "$out" | grep -q 'Traceback'; then
        failures+=("$backend -s 1979: crashed")
        continue
    fi
    if [ "$rows" -ne 2 ]; then
        failures+=("$backend -s 1979: expected 1 scene row, got $((rows - 1))")
    fi
    first=$(printf '%s\n' "$out" | grep '^ |' | sed -n 2p)
    start_frame=$(printf '%s' "$first" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
    if [ "$start_frame" != "1979" ]; then
        failures+=("$backend -s 1979: scene starts at frame [$start_frame], expected 1979")
    fi
done

for backend in pyav opencv; do
    out=$(run "$backend")
    printf '%s\n' "$out" | grep -q 'Traceback' && { failures+=("$backend full: crashed"); continue; }
    printf '%s\n' "$out" > "/tmp/ghost_${backend}.txt"
done

python3 - <<'EOF'
import re, sys

failures = []
for backend in ("pyav", "opencv"):
    rows = []
    for line in open(f"/tmp/ghost_{backend}.txt"):
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]]
        if not cells or not cells[0].isdigit():
            continue
        rows.append(cells)
    if len(rows) < 2:
        failures.append(f"{backend} full: expected multiple scenes, got {len(rows)}")
        continue
    expected_start = 1
    for cells in rows:
        start, end = int(cells[1]), int(cells[3])
        if not (1 <= start <= end <= 1980):
            failures.append(f"{backend}: scene {cells[0]} range {start}..{end} out of 1..1980")
        if start != expected_start:
            failures.append(
                f"{backend}: scene {cells[0]} starts at {start}, expected {expected_start}")
        expected_start = end + 1
    if expected_start - 1 != 1980:
        failures.append(f"{backend}: final scene ends at {expected_start - 1}, expected 1980")
if failures:
    print("FAIL check6_no_ghost_scenes")
    [print("  -", f) for f in failures]
    sys.exit(1)
print("PASS check6_no_ghost_scenes: -s 1979 yields exactly one scene; full pass is "
      "contiguous 1..1980 with no phantom scenes")
EOF
status=$?
rm -f /tmp/ghost_pyav.txt /tmp/ghost_opencv.txt
if [ "${#failures[@]}" -ne 0 ]; then
    printf 'FAIL check6_no_ghost_scenes (CLI)\n'
    for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit "$status"
