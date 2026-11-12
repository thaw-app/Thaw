#!/bin/sh
set -eu

# Rewrites .swiftlint.baseline from a fresh lint run when it only shrinks:
# run it after making a grandfathered file or function smaller.

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Lint fails while the baseline is out of date, which is why this runs.
sh "$ROOT/scripts/lint.sh" --quiet --write-baseline "$TMP/fresh.json" >/dev/null || true
[ -s "$TMP/fresh.json" ] || {
    echo "error: SwiftLint didn't write a baseline; run sh scripts/lint.sh to see why." >&2
    exit 1
}
python3 "$ROOT/scripts/swiftlint-baseline.py" update "$ROOT/.swiftlint.baseline" "$TMP/fresh.json"
