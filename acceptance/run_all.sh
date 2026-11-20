#!/usr/bin/env bash
# Runs all 8 acceptance checks for the cut-artifact / frame-numbering fix.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for script in "$HERE"/0[1-8]_*.sh; do
    echo "================================================================"
    echo "RUN: $(basename "$script")"
    echo "================================================================"
    bash "$script"
    echo
done
echo "ALL 8 ACCEPTANCE SCRIPTS PASSED"
