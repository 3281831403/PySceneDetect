#!/usr/bin/env bash
# Acceptance 2/8: --merge-last-scene makes the cut artifacts match the final scene list's
# internal boundaries. The testvideo report mentioned a stale cut at frame 394; this verifies
# (a) the controller merge path drops the merged-away boundary, and (b) the end-to-end CLI
# keyframes/QP/CSV cuts equal the surviving scenes' internal boundaries.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/testvideo.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
SD="python3 -m scenedetect"

# (a) Controller merge path: default detection yields 4 raw scenes
# (0,30),(30,180),(180,394),(394,720); a 330-frame minimum merges the 326-frame final scene.
python3 - "$VIDEO" <<'EOF'
import sys

from scenedetect import ContentDetector, FrameTimecode, SceneManager
from scenedetect._cli.context import CliContext
from scenedetect._cli.controller import _postprocess_scene_list
from scenedetect.backends import VideoStreamCv2
from scenedetect.scene_manager import get_cuts_from_scenes

video = VideoStreamCv2(sys.argv[1])
scene_manager = SceneManager()
scene_manager.add_detector(ContentDetector())
scene_manager.detect_scenes(video)
raw = scene_manager.get_scene_list(start_in_scene=True)
assert [start.frame_num for start, _ in raw] == [0, 30, 180, 394]

context = CliContext()
context.merge_last_scene = True
context.drop_short_scenes = False
context.min_scene_len = FrameTimecode(330, video.frame_rate)
merged = _postprocess_scene_list(context, raw)
assert [(s.frame_num, e.frame_num) for s, e in merged] == [(0, 30), (30, 180), (180, 720)]
cuts = get_cuts_from_scenes(merged)
assert [cut.frame_num for cut in cuts] == [30, 180], cuts
assert 394 not in [cut.frame_num for cut in cuts]
print("  ok: controller merge -> 3 scenes, cuts [30, 180], stale 394 removed")
EOF

# (b) End-to-end CLI: the detector-level -m 0 override keeps all 4 raw cuts so the controller's
# merge step actually runs; the cut files must then contain exactly the surviving boundaries.
$SD -q -i "$VIDEO" -o "$WORK" --min-scene-len 330 --merge-last-scene \
    detect-content -m 0 list-scenes save-keyframes save-qp

python3 - "$WORK/testvideo-Scenes.csv" "$WORK/testvideo-keyframes.txt" "$WORK/testvideo.qp" <<'EOF'
import csv, sys

csv_path, kf_path, qp_path = sys.argv[1:]
rows = list(csv.reader(open(csv_path)))
data = rows[2:]
assert len(data) == 3, len(data)

# Scenes join contiguously: exclusive End Frame of scene N + 1 == next scene's Start Frame.
for a, b in zip(data, data[1:]):
    assert int(a[4]) + 1 == int(b[1]), (a, b)

start_frames = [int(row[1]) for row in data[1:]]
assert start_frames == [31, 181], start_frames
assert rows[0][1:] == [row[2] for row in data[1:]]

kf = [int(line) for line in open(kf_path).read().splitlines()[2:]]
assert kf[0] == 0 and kf[1:] == start_frames, kf
qp = [int(line.split(" ")[0]) for line in open(qp_path).read().splitlines()]
assert qp[0] == 0 and qp[1:] == start_frames, qp
print("  ok: e2e merge -> 3 scenes, 2 cuts [31, 181] in CSV/keyframes/QP, 394 absent")
EOF
echo "ACCEPT 2 PASS: merge-last-scene cut artifacts equal final scene boundaries"
