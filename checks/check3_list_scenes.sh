#!/usr/bin/env bash
# Check 3: list-scenes frame numbers are real presentation ordinals and refer to the
# same frame as the timecode on the same row, verified against ffprobe ground truth.
#
# CSV convention (unchanged from CFR): "Start Frame" is the 1-based ordinal of the
# scene's first frame; "End Frame" is the 0-based ordinal of the frame the next scene
# starts at (so the final scene ends at the total frame count). Each row's frame number
# must name the frame whose PTS is the row's timecode. Previously 43 of 44 boundaries
# on goldeneye-vfr.mp4 (PyAV) failed this.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for b in pyav opencv; do
    mkdir -p "$WORK/$b"
    python3 -m scenedetect -q -i tests/resources/goldeneye-vfr.mp4 -b "$b" \
        -o "$WORK/$b" detect-content list-scenes >/dev/null 2>&1
done

python3 - "$WORK" <<'EOF'
import csv, subprocess, sys

work = sys.argv[1]
out = subprocess.run(
    ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=pts_time",
     "-of", "csv=p=0", "tests/resources/goldeneye-vfr.mp4"],
    capture_output=True, text=True, check=True).stdout
pts = [float(l.rstrip(",")) for l in out.strip().split("\n")]
duration = pts[-1] + (pts[-1] - pts[-2])  # one-past-the-end presentation time

def tc2sec(tc):
    h, m, s = tc.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)

failures = []
tables = {}
for backend in ("pyav", "opencv"):
    with open(f"{work}/{backend}/goldeneye-vfr-Scenes.csv") as f:
        next(f)  # "Timecode List:" row
        rows = list(csv.DictReader(f))
    tables[backend] = [(r["Start Frame"], r["Start Timecode"], r["End Frame"],
                        r["End Timecode"]) for r in rows]
    for r in rows:
        for col_f, col_t, off in (("Start Frame", "Start Timecode", -1),
                                  ("End Frame", "End Timecode", 0)):
            frame = int(r[col_f])
            t = tc2sec(r[col_t])
            idx = frame + off
            if 0 <= idx < len(pts):
                expected = pts[idx]
            elif idx == len(pts):
                expected = duration
            else:
                expected = None
            if expected is None or abs(expected - t) > 0.0006:
                failures.append(
                    f"{backend} scene {r['Scene Number']}: {col_f} {frame} with {col_t} "
                    f"{r[col_t]} are not the same frame (PTS there is "
                    f"{None if expected is None else round(expected, 6)})"
                )

# Both backends must produce the same scene table.
if tables["pyav"] != tables["opencv"]:
    failures.append("pyav and opencv scene tables differ")

if failures:
    print("FAIL check3_list_scenes")
    [print("  -", f) for f in failures]
    sys.exit(1)
n = len(tables["pyav"])
print(f"PASS check3_list_scenes: all {2 * n} boundaries on {n} scenes are real ordinals "
      f"matching their timecodes, identical across backends")
EOF
