#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IFS= read -r expected < "$ROOT/.swiftlint-version"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: SwiftLint $expected is required. See .github/CONTRIBUTING.md#code-style." >&2
    exit 1
fi

actual=$(swiftlint version)
if [ "$actual" != "$expected" ]; then
    echo "error: SwiftLint $expected is required; found $actual. See .github/CONTRIBUTING.md#code-style." >&2
    exit 1
fi

cd "$ROOT"
exec swiftlint lint "$@"
