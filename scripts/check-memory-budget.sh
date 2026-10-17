#!/usr/bin/env bash
# Fails when Thaw holds more live heap than the budget after drawing Settings and Search off screen.
# Heap, not footprint: the footprint swings by tens of megabytes between runs.
#
# Usage:
#   ./scripts/check-memory-budget.sh <path to Thaw.app/Contents/MacOS/Thaw> [megabytes]   # 80 MB unless given
set -euo pipefail

BINARY="${1:?usage: check-memory-budget.sh <Thaw binary> [megabytes]}"
LIMIT="${2:-80}"

output="$("$BINARY" --bench-memory 2>&1 || true)"
grep -E '^(STEP|FOOTPRINT|HEAP)' <<<"$output" || true

heap=$(sed -nE 's/^HEAP ([0-9]+(\.[0-9]+)?).*/\1/p' <<<"$output")
if [[ -z "$heap" ]]; then
    # No figure means the bench did not finish: a crash, or a machine that cannot draw windows.
    tail -n 5 <<<"$output" >&2
    echo "::error::The memory bench reported no heap figure, so the budget could not be checked." >&2
    exit 1
fi
# Compared as decimals, so 80.9 MB is over an 80 MB budget.
if awk -v heap="$heap" -v limit="$LIMIT" 'BEGIN { exit !(heap > limit) }'; then
    echo "::error::Thaw holds ${heap} MB of heap after drawing Settings and Search, over the budget of ${LIMIT} MB." >&2
    exit 1
fi
echo "Thaw holds ${heap} MB of heap after drawing Settings and Search, within the budget of ${LIMIT} MB."
