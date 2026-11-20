#!/usr/bin/env bash
# Acceptance 7/8: the list-scenes -> load-scenes round trip is preserved byte-for-byte, and
# re-loading a CSV with --merge-last-scene still yields cuts derived from the final scene list.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/testvideo.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
SD="python3 -m scenedetect"

# Plain round-trip over the whole video must be byte-identical.
$SD -q -i "$VIDEO" -o "$WORK" detect-content list-scenes -f first.csv
$SD -q -i "$VIDEO" -o "$WORK" load-scenes -i "$WORK/first.csv" list-scenes -f second.csv
diff "$WORK/first.csv" "$WORK/second.csv"
echo "  ok: load-scenes round-trip CSV is byte-identical"

# Round-trip with merge: scenes join contiguously and cuts equal the internal join points.
$SD -q -i "$VIDEO" -o "$WORK" --min-scene-len 330 --merge-last-scene \
    load-scenes -i "$WORK/first.csv" list-scenes -f merged.csv save-keyframes

python3 - "$WORK/merged.csv" "$WORK/testvideo-keyframes.txt" <<'EOF'
import csv, sys

csv_path, kf_path = sys.argv[1:]
rows = list(csv.reader(open(csv_path)))
data = rows[2:]
assert len(data) == 3, len(data)
# Contiguous join: exclusive End Frame of scene N + 1 == next scene's Start Frame.
for a, b in zip(data, data[1:]):
    assert int(a[4]) + 1 == int(b[1]), (a, b)
start_frames = [int(row[1]) for row in data[1:]]
assert rows[0][1:] == [row[2] for row in data[1:]]
kf = [int(line) for line in open(kf_path).read().splitlines()[2:]]
assert kf[0] == 0 and kf[1:] == start_frames == [31, 181], (kf, start_frames)
print(f"  ok: merge after load -> 3 scenes, cuts {start_frames} match keyframes {kf}")
EOF
echo "ACCEPT 7 PASS: load-scenes round trip and post-processed re-load preserved"
