#!/usr/bin/env bash
# Check 2: frame_number equals the actual number of read() calls, on both backends.
#
# Reading all 1980 frames of goldeneye-vfr.mp4 used to leave PyAV's frame_number
# at 2888 (a PTS*fps approximation) instead of 1980.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'EOF'
import sys
from scenedetect.backends.opencv import VideoStreamCv2
from scenedetect.backends.pyav import VideoStreamAv

TOTAL_FRAMES = 1980
CHECKPOINTS = {1, 2, 100, 500, 1000, 1979, 1980}
failures = []
for cls in (VideoStreamCv2, VideoStreamAv):
    v = cls("tests/resources/goldeneye-vfr.mp4")
    if v.frame_number != 0:
        failures.append(f"{cls.BACKEND_NAME}: frame_number {v.frame_number} before first read")
    n = 0
    while v.read() is not False:
        n += 1
        if n in CHECKPOINTS and v.frame_number != n:
            failures.append(
                f"{cls.BACKEND_NAME}: after {n} reads frame_number is {v.frame_number}"
            )
        # The position ordinal must be the 0-based decode count as well.
        if n in CHECKPOINTS and v.position.frame_index != n - 1:
            failures.append(
                f"{cls.BACKEND_NAME}: after {n} reads position ordinal is "
                f"{v.position.frame_index}"
            )
    if n != TOTAL_FRAMES:
        failures.append(f"{cls.BACKEND_NAME}: read {n} frames, expected {TOTAL_FRAMES}")
    if v.frame_number != TOTAL_FRAMES:
        failures.append(
            f"{cls.BACKEND_NAME}: frame_number {v.frame_number} != {TOTAL_FRAMES} at EOF"
        )
    v.close()

if failures:
    print("FAIL check2_frame_number")
    [print("  -", f) for f in failures]
    sys.exit(1)
print(f"PASS check2_frame_number: frame_number == read count on both backends "
      f"(full pass = {TOTAL_FRAMES})")
EOF
