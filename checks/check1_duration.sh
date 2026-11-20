#!/usr/bin/env bash
# Check 1: duration equals the true PTS end (120.453667s) and both backends agree.
#
# goldeneye-vfr.mp4 is a VFR video: 1980 frames, true presentation end 120.453667s.
# The PyAV backend used to report 82.58s (nominal frame count / nominal fps).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'EOF'
import sys
from scenedetect.backends.opencv import VideoStreamCv2
from scenedetect.backends.pyav import VideoStreamAv

TRUE_END = 120.453667  # ffprobe stream/format duration of goldeneye-vfr.mp4
TOTAL_FRAMES = 1980
failures = []
durations = {}
for cls in (VideoStreamCv2, VideoStreamAv):
    v = cls("tests/resources/goldeneye-vfr.mp4")
    # Duration must be available (and correct) before decoding anything.
    sec = v.duration.seconds
    tc = v.duration.get_timecode()
    durations[cls.BACKEND_NAME] = (sec, tc)
    if abs(sec - TRUE_END) > 0.001:
        failures.append(f"{cls.BACKEND_NAME}: duration {sec:.6f}s != true PTS end {TRUE_END}s")
    if tc != "00:02:00.454":
        failures.append(f"{cls.BACKEND_NAME}: duration timecode {tc} != 00:02:00.454")
    # After a full pass the exact frame count must be attached and equal the total.
    while v.read() is not False:
        pass
    if v.duration.frame_index != TOTAL_FRAMES:
        failures.append(
            f"{cls.BACKEND_NAME}: duration ordinal after full pass "
            f"{v.duration.frame_index} != {TOTAL_FRAMES}"
        )
    v.close()

if durations["pyav"][1] != durations["opencv"][1]:
    failures.append(f"backends disagree on duration: {durations}")
if abs(durations["pyav"][0] - durations["opencv"][0]) > 0.001:
    failures.append(f"backends disagree on duration seconds: {durations}")

if failures:
    print("FAIL check1_duration")
    [print("  -", f) for f in failures]
    sys.exit(1)
print(f"PASS check1_duration: both backends report {durations['pyav'][1]} "
      f"({durations['pyav'][0]:.6f}s), ordinal {TOTAL_FRAMES}")
EOF
