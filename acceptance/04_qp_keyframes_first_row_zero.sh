#!/usr/bin/env bash
# Acceptance 4/8: tool-facing cut files (save-qp / save-keyframes) keep their frame-0 first
# row, while all cut entries use the CLI's 1-based frame numbers. The shifted/--disable-shift
# QP semantics remain intact.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/goldeneye.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
SD="python3 -m scenedetect"

# No time window: one cut in range (0-based frame 90 -> CLI frame 91).
$SD -q -i "$VIDEO" -o "$WORK" time -e 95 detect-content save-qp save-keyframes
[ "$(cat "$WORK/goldeneye.qp")" = "$(printf '0 I -1\n91 I -1')" ]
[ "$(cat "$WORK/goldeneye-keyframes.txt")" = "$(printf '# keyframe format v1\nfps 0\n0\n91')" ]
rm -f "$WORK"/*

# Start offset 51 with shift: QP re-bases to 0 and shifts the 1-based cut (91 - 50 = 41);
# keyframes keep absolute ordinals. The frame-0 first row is preserved in both files.
$SD -q -i "$VIDEO" -o "$WORK" time -s 51 -e 95 detect-content save-qp save-keyframes
[ "$(cat "$WORK/goldeneye.qp")" = "$(printf '0 I -1\n41 I -1')" ]
[ "$(head -1 "$WORK/goldeneye.qp")" = "0 I -1" ]
[ "$(sed -n '3p' "$WORK/goldeneye-keyframes.txt")" = "0" ]
[ "$(tail -1 "$WORK/goldeneye-keyframes.txt")" = "91" ]
rm -f "$WORK"/*

# --disable-shift writes the absolute 0-based start frame first, then the absolute 1-based cut.
$SD -q -i "$VIDEO" -o "$WORK" time -s 51 -e 95 detect-content save-qp --disable-shift
[ "$(cat "$WORK/goldeneye.qp")" = "$(printf '50 I -1\n91 I -1')" ]

echo "  ok: QP/keyframes first row stays 0 (or the unshifted start), cuts are CLI 1-based"
echo "ACCEPT 4 PASS: frame-0 first row preserved with 1-based cut entries"
