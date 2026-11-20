#!/usr/bin/env bash
# Acceptance 6/8: invariant CFR/VFR outputs are untouched.
#  - The stats file still has 720 lines (1 header + 719 per-frame rows, frames 2..720).
#  - Per-scene split clips still cover the full CFR input contiguously (the "join" invariant:
#    clip durations sum to the source duration), so re-concatenation reproduces the source.
#  - VFR cut artifacts keep the same scene/cut consistency.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/testvideo.mp4"
VFR_VIDEO="$REPO/tests/resources/goldeneye-vfr.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
SD="python3 -m scenedetect"

# --- Stats file line count and frame numbering must be exactly as before. ---
$SD -q -i "$VIDEO" -o "$WORK" -s "$WORK/stats.csv" detect-content list-scenes >/dev/null
LINES=$(wc -l < "$WORK/stats.csv")
FIRST=$(sed -n '2p' "$WORK/stats.csv" | cut -d, -f1)
LAST=$(tail -1 "$WORK/stats.csv" | cut -d, -f1)
echo "stats lines=$LINES first_frame=$FIRST last_frame=$LAST"
[ "$LINES" -eq 720 ]
[ "$FIRST" = "2" ]
[ "$LAST" = "720" ]

# --- Per-scene split clips join back to the source duration. ---
$SD -q -i "$VIDEO" -o "$WORK" detect-content split-video \
    -a '-v error -map 0:v:0 -c:v libx264 -preset ultrafast' >/dev/null
SRC_FRAMES=$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of default=nw=1:nk=1 "$VIDEO")
JOINED=0
for clip in "$WORK"/*.mp4; do
    N=$(ffprobe -v error -count_frames -select_streams v:0 \
        -show_entries stream=nb_read_frames -of default=nw=1:nk=1 "$clip")
    JOINED=$((JOINED + N))
done
echo "source frames=$SRC_FRAMES joined clip frames=$JOINED"
[ "$JOINED" -eq "$SRC_FRAMES" ]

# --- VFR: scenes remain contiguous and cut artifacts stay mutually consistent. ---
VFR_OUT="$WORK/vfr"
mkdir -p "$VFR_OUT"
$SD -q -i "$VFR_VIDEO" -o "$VFR_OUT" detect-content list-scenes save-keyframes save-qp
python3 - "$VFR_OUT/goldeneye-vfr-Scenes.csv" \
    "$VFR_OUT/goldeneye-vfr-keyframes.txt" "$VFR_OUT/goldeneye-vfr.qp" <<'EOF'
import csv, sys

csv_path, kf_path, qp_path = sys.argv[1:]
rows = list(csv.reader(open(csv_path)))
data = rows[2:]
assert len(data) > 1
# Cuts equal the internal scene boundaries.
assert rows[0][1:] == [row[2] for row in data[1:]]
for a, b in zip(data, data[1:]):
    assert int(a[4]) + 1 == int(b[1]), (a, b)
start_frames = [int(row[1]) for row in data[1:]]
kf = [int(line) for line in open(kf_path).read().splitlines()[2:]]
qp = [int(line.split(" ")[0]) for line in open(qp_path).read().splitlines()]
assert kf[0] == 0 and kf[1:] == start_frames
assert qp[0] == 0 and qp[1:] == start_frames
print(f"  ok: VFR {len(data)} scenes join contiguously, cuts match keyframes/QP")
EOF
echo "ACCEPT 6 PASS: CFR 719 stats rows, per-scene join and VFR outputs unchanged"
