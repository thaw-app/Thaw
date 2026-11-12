#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IFS= read -r expected < "$ROOT/.swiftformat-version"
# Where install-swiftformat.sh puts the pinned version.
PATH="${HOME:-}/.local/bin:$PATH"

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "error: SwiftFormat $expected is required. Install it with: sh scripts/install-swiftformat.sh" >&2
    exit 1
fi

actual=$(swiftformat --version)
if [ "$actual" != "$expected" ]; then
    echo "error: SwiftFormat $expected is required; found $actual. Install it with: sh scripts/install-swiftformat.sh" >&2
    exit 1
fi

cd "$ROOT"
exec swiftformat . "$@"
