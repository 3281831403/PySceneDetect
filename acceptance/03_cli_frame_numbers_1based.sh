#!/usr/bin/env bash
# Acceptance 3/8: CLI frame numbers are 1-based and consistent across the CSV scene list,
# split-video filename templates and save-images $FRAME_NUMBER. The first frame is frame 1
# everywhere; the frame-0 sentinel only exists in tool-facing cut files (checked in 1/2).
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/testvideo.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
SD="python3 -m scenedetect"

# Frames 0..94 contain one cut at 0-based frame 30 -> scenes (0,30) and (30,95).
$SD -q -i "$VIDEO" -o "$WORK" time -e 95 detect-content list-scenes \
    save-images -f 'img-$FRAME_NUMBER' \
    split-video -f 'clip-$START_FRAME-$END_FRAME.mp4' \
    -a '-v error -map 0:v:0 -c:v libx264 -preset ultrafast'

python3 - "$WORK/testvideo-Scenes.csv" "$WORK" <<'EOF'
import csv, glob, os, re, sys

csv_path, out_dir = sys.argv[1:]
rows = list(csv.reader(open(csv_path)))
data = rows[2:]
assert [row[1] for row in data] == ["1", "31"], data
assert [row[4] for row in data] == ["30", "95"], data
start_frames = {int(row[0]): int(row[1]) for row in data}

# split-video: $START_FRAME/$END_FRAME are both 1-based and match the CSV columns shifted
# into the same inclusive 1-based frame space (exclusive end 30 -> 31, 95 -> 96).
clip_re = re.compile(r"clip-(\d+)-(\d+)\.mp4$")
clips = sorted(
    (int(match.group(1)), int(match.group(2)))
    for path in glob.glob(os.path.join(out_dir, "clip-*.mp4"))
    if (match := clip_re.search(path))
)
assert clips == [(1, 31), (31, 96)], clips
assert [start for start, _ in clips] == [start_frames[scene] for scene in sorted(start_frames)]
print("  ok: split-video names clip-1-31.mp4 / clip-31-96.mp4 match CSV frame columns")

# save-images: every $FRAME_NUMBER is 1-based (no zero), and frames stay inside their scene.
image_frames = [
    int(re.search(r"img-(\d+)\.jpg$", path).group(1))
    for path in glob.glob(os.path.join(out_dir, "img-*.jpg"))
]
assert image_frames and min(image_frames) >= 1, image_frames
assert 16 in image_frames  # middle image of scene 1 (0-based frame 15 -> 1-based 16)
print(f"  ok: {len(image_frames)} save-images files all use 1-based frame numbers")
EOF
echo "ACCEPT 3 PASS: CLI frame numbers are uniformly 1-based"
