#!/usr/bin/env bash
# Check 8: the non-release test suite does not regress (711 passed, 3 skipped).
set -euo pipefail
cd "$(dirname "$0")/.."

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
python3 -m pytest tests/ -q -p no:cacheprovider > "$LOG" 2>&1 || {
    tail -20 "$LOG"
    echo "FAIL check8_tests: pytest exited non-zero"
    exit 1
}
tail -1 "$LOG"
if grep -qE '^[0-9]+ passed' <(tail -1 "$LOG"); then
    echo "PASS check8_tests: full suite passes"
else
    echo "FAIL check8_tests: unexpected pytest summary"
    exit 1
fi
