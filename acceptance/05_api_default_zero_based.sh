#!/usr/bin/env bash
# Acceptance 5/8: the Python API defaults are unchanged (0-based). Only the CLI layer requests
# 1-based frame numbers; direct callers of save_images() and default_formatter() keep their
# historical behavior unless they explicitly opt in via one_based_frame_numbers=True.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
VIDEO="$REPO/tests/resources/testvideo.mp4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"

python3 - "$VIDEO" "$WORK" <<'EOF'
import sys
from fractions import Fraction
from pathlib import Path

from scenedetect import FrameTimecode, VideoStreamCv2, save_images
from scenedetect.output import SceneMetadata, VideoMetadata, default_formatter

video_path, out_dir = sys.argv[1], Path(sys.argv[2])
fps = VideoStreamCv2(video_path).frame_rate
# A one-frame scene at 0-based frame 11: the saved image must name that exact frame.
scene = [(FrameTimecode(11, fps), FrameTimecode(12, fps))]

for threading in (True, False):
    default_names = save_images(
        scene,
        VideoStreamCv2(video_path),
        num_images=1,
        output_dir=out_dir / f"default_{threading}",
        image_name_template="$SCENE_NUMBER.$FRAME_NUMBER",
        threading=threading,
    )
    assert default_names == {0: ["001.11.jpg"]}, (threading, default_names)

    one_based_names = save_images(
        scene,
        VideoStreamCv2(video_path),
        num_images=1,
        output_dir=out_dir / f"one_based_{threading}",
        image_name_template="$SCENE_NUMBER.$FRAME_NUMBER",
        threading=threading,
        one_based_frame_numbers=True,
    )
    assert one_based_names == {0: ["001.12.jpg"]}, (threading, one_based_names)
print("  ok: save_images() stays 0-based by default, 1-based only on explicit opt-in")

# default_formatter: 0-based unless requested.
meta = VideoMetadata(name="v", path=Path("v.mp4"), total_scenes=1)
scene_meta = SceneMetadata(
    index=0, start=FrameTimecode(0, Fraction(30, 1)), end=FrameTimecode(60, Fraction(30, 1))
)
assert default_formatter("$START_FRAME-$END_FRAME")(meta, scene_meta) == "0-60"
assert (
    default_formatter("$START_FRAME-$END_FRAME", one_based_frame_numbers=True)(
        meta, scene_meta
    )
    == "1-61"
)
print("  ok: default_formatter() is 0-based by default, 1-based only on opt-in")
EOF
echo "ACCEPT 5 PASS: Python API 0-based default is unchanged"
