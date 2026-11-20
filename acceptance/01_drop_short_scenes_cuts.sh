#!/usr/bin/env bash
# Acceptance 1/8: --drop-short-scenes makes every cut-based artifact (CSV cut row, terminal
# cut list, save-keyframes, save-qp, save-html) match the final scene list's internal
# boundaries instead of the raw 22 detector cuts.
#
# Reproduces the goldeneye report: after dropping short scenes there are 8 scenes, so every
# artifact must contain exactly 7 cuts.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/goldeneye.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
SD="python3 -m scenedetect"

$SD -q -i "$VIDEO" -o "$WORK" --min-scene-len 4.0s --drop-short-scenes \
    detect-content list-scenes save-keyframes save-qp save-html --no-images

CSV="$WORK/goldeneye-Scenes.csv"
KF="$WORK/goldeneye-keyframes.txt"
QP="$WORK/goldeneye.qp"
HTML="$WORK/goldeneye-Scenes.html"

python3 - "$CSV" "$KF" "$QP" "$HTML" <<'EOF'
import csv, re, sys

csv_path, kf_path, qp_path, html_path = sys.argv[1:]
rows = list(csv.reader(open(csv_path)))
data = rows[2:]
num_scenes = len(data)
assert num_scenes == 8, num_scenes

# CSV: the first row carries exactly N-1 cut timecodes, equal to the scenes' start timecodes.
csv_cuts = rows[0][1:]
start_timecodes = [row[2] for row in data[1:]]
assert len(csv_cuts) == num_scenes - 1 == 7
assert csv_cuts == start_timecodes, (csv_cuts, start_timecodes)

# 1-based Start Frame of every scene but the first is the canonical cut frame number.
start_frames = [int(row[1]) for row in data[1:]]

# Keyframes: 2 header lines, the frame-0 sentinel, then one 1-based entry per cut.
kf_lines = open(kf_path).read().splitlines()
assert kf_lines[:2] == ["# keyframe format v1", "fps 0"]
kf_frames = [int(line) for line in kf_lines[2:]]
assert kf_frames[0] == 0 and kf_frames[1:] == start_frames, kf_frames

# QP: the first row is the frame-0 sentinel, then one 1-based entry per cut.
qp_frames = [int(line.split(" ")[0]) for line in open(qp_path).read().splitlines()]
assert qp_frames[0] == 0 and qp_frames[1:] == start_frames, qp_frames

# HTML timecode table shows the same 7 cut timecodes as the CSV.
html = open(html_path).read()
table = html.split("</table>")[0]
html_cells = re.findall(r"<td[^>]*>(.*?)</td>", table)
assert html_cells[0] == "Timecode List:"
assert html_cells[1:] == csv_cuts, (html_cells, csv_cuts)

print(f"  ok: 8 scenes -> 7 cuts consistent across CSV/HTML/keyframes/QP: {start_frames}")
print("  ok: keyframes and QP keep the frame-0 first row, cuts are 1-based")
EOF
echo "ACCEPT 1 PASS: drop-short-scenes cut artifacts equal final scene boundaries"
