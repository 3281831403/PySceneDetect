#!/usr/bin/env bash
# Check 4: processing the complete file, the final scene's End equals the total frame
# count (1980) and the true end of the video (00:02:00.454), on both backends.
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
total = int(subprocess.run(
    ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=nb_frames",
     "-of", "csv=p=0", "tests/resources/goldeneye-vfr.mp4"],
    capture_output=True, text=True, check=True).stdout.strip())

failures = []
for backend in ("pyav", "opencv"):
    with open(f"{work}/{backend}/goldeneye-vfr-Scenes.csv") as f:
        next(f)
        rows = list(csv.DictReader(f))
    last = rows[-1]
    if int(last["End Frame"]) != total:
        failures.append(
            f"{backend}: final End Frame {last['End Frame']} != total frames {total}")
    if last["End Timecode"] != "00:02:00.454":
        failures.append(
            f"{backend}: final End Timecode {last['End Timecode']} != 00:02:00.454")

if failures:
    print("FAIL check4_end_equals_total")
    [print("  -", f) for f in failures]
    sys.exit(1)
print(f"PASS check4_end_equals_total: final End is frame {total} @ 00:02:00.454 "
      f"on both backends")
EOF
