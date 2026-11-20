#!/usr/bin/env bash
# Check 5: `-s N` (and VideoStream.seek(N)) lands exactly on frame N on VFR video, on
# both backends, matching the frame a sequential read produces there. CFR must stay exact.
#
# Before the fix PyAV started at frame 102 and OpenCV at frame 98 for `-s 100`.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'EOF'
import subprocess, sys
from scenedetect import open_video
from scenedetect.backends.opencv import VideoStreamCv2
from scenedetect.backends.pyav import VideoStreamAv

VFR = "tests/resources/goldeneye-vfr.mp4"
CFR = "tests/resources/goldeneye.mp4"


def ground_truth_pts(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=pts_time",
         "-of", "csv=p=0", path], capture_output=True, text=True, check=True).stdout
    return [float(l.rstrip(",")) for l in out.strip().split("\n")]


failures = []
for cls in (VideoStreamCv2, VideoStreamAv):
    name = cls.BACKEND_NAME
    # VFR: seek(N) then read() must land on the frame at 0-based ordinal N.
    pts = ground_truth_pts(VFR)
    for target in (1, 2, 98, 99, 100, 101, 500, 1500):
        v = cls(VFR)
        v.seek(target)
        # Before the read the stream holds the frame before the target.
        if v.frame_number != target:
            failures.append(f"{name} VFR seek({target}): frame_number {v.frame_number} != {target}")
        if v.read(decode=False) is False:
            failures.append(f"{name} VFR seek({target}): read failed")
        else:
            if v.frame_number != target + 1:
                failures.append(
                    f"{name} VFR seek({target}): next frame_number {v.frame_number} != {target + 1}")
            if v.position.frame_index != target:
                failures.append(
                    f"{name} VFR seek({target}): ordinal {v.position.frame_index} != {target}")
            if abs(v.position.seconds - pts[target]) > 0.0006:
                failures.append(
                    f"{name} VFR seek({target}): PTS {v.position.seconds:.6f} != {pts[target]:.6f}")
        v.close()
    # CFR: the same seeks must land exactly (they always did).
    cfr_pts = ground_truth_pts(CFR)
    for target in (1, 99, 100, 101):
        v = cls(CFR)
        v.seek(target)
        v.read(decode=False)
        if v.position.frame_index != target:
            failures.append(
                f"{name} CFR seek({target}): ordinal {v.position.frame_index} != {target}")
        if abs(v.position.seconds - cfr_pts[target]) > 0.0006:
            failures.append(
                f"{name} CFR seek({target}): PTS {v.position.seconds:.6f} != {cfr_pts[target]:.6f}")
        v.close()

# CLI: `time -s 100` must start the first scene at 1-based frame 100.
for backend in ("pyav", "opencv"):
    result = subprocess.run(
        [sys.executable, "-m", "scenedetect", "-i", VFR, "-b", backend,
         "time", "-s", "100", "detect-content", "list-scenes"],
        capture_output=True, text=True)
    table = [line for line in result.stdout.splitlines() if line.strip().startswith("|")]
    if not table:
        failures.append(f"CLI {backend} -s 100: no scene table")
        continue
    first = [c.strip() for c in table[1].split("|")[1:-1]]
    if first[1] != "100":
        failures.append(f"CLI {backend} -s 100: first Start Frame {first[1]} != 100")
    pts = ground_truth_pts(VFR)
    h, m, s = first[2].split(":")
    start_secs = int(h) * 3600 + int(m) * 60 + float(s)
    if abs(start_secs - pts[99]) > 0.0006:
        failures.append(f"CLI {backend} -s 100: start time {first[2]} != PTS of frame 100")

if failures:
    print("FAIL check5_seek_exact")
    [print("  -", f) for f in failures]
    sys.exit(1)
print("PASS check5_seek_exact: seek(100)/read() lands on the 101st frame (ordinal 100) "
      "on both backends; CLI -s 100 starts at frame 100")
EOF
