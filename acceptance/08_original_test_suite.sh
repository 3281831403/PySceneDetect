#!/usr/bin/env bash
# Acceptance 8/8: the original test suite is unchanged. The pre-change baseline was
# "711 passed, 3 skipped, 83 deselected"; this script asserts the same 711 historical tests
# still pass after excluding the regression tests added with the fix.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO"
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"

OUT=$(python3 -m pytest tests/ -q \
    --deselect 'tests/test_output.py::test_save_images_frame_number_basis[True]' \
    --deselect 'tests/test_output.py::test_save_images_frame_number_basis[False]' \
    --deselect tests/test_output.py::test_default_formatter_frame_number_basis \
    --deselect tests/test_output.py::test_get_cuts_from_scenes \
    --deselect tests/test_cli.py::test_cli_drop_short_scenes_cuts_match_scenes \
    --deselect tests/test_cli.py::test_cli_merge_last_scene_unit_cuts_match_scenes \
    --deselect tests/test_cli.py::test_cli_drop_short_scenes_unit_cuts_match_scenes \
    --deselect tests/test_cli.py::test_cli_frame_numbers_are_1based 2>&1)
echo "$OUT" | tail -3
# Explicit --deselect entries are added to the 83 release-marked tests, so only the passed and
# skipped counts are asserted against the baseline.
echo "$OUT" | grep -qE "711 passed, 3 skipped"
echo "ACCEPT 8 PASS: all 711 pre-existing tests still pass"
