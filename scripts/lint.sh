#!/bin/sh
set -eu

# The real path: under a symlink such as /tmp, SwiftLint ignores the baseline.
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
IFS= read -r expected < "$ROOT/.swiftlint-version"
# Where install-swiftlint.sh puts the pinned version; Xcode's PATH leaves it out.
PATH="${HOME:-}/.local/bin:$PATH"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: SwiftLint $expected is required. Install it with: sh scripts/install-swiftlint.sh" >&2
    exit 1
fi

actual=$(swiftlint version)
if [ "$actual" != "$expected" ]; then
    echo "error: SwiftLint $expected is required; found $actual. Install it with: sh scripts/install-swiftlint.sh" >&2
    exit 1
fi

cd "$ROOT"
exec swiftlint lint "$@"
