#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
CHECKOUT="$TEMP_DIR/checkout with spaces"
BIN="$TEMP_DIR/bin"
mkdir -p "$CHECKOUT/scripts" "$BIN"
cp "$ROOT/scripts/lint.sh" "$CHECKOUT/scripts/"
cp "$ROOT/.swiftlint-version" "$CHECKOUT/"
ln -s "$(command -v dirname)" "$BIN/dirname"
IFS= read -r VERSION < "$ROOT/.swiftlint-version"

run_lint() {
    local expected_status=$1 actual_status=0
    shift
    (cd "$TEMP_DIR" && HOME="$TEMP_DIR/home" PATH="$BIN" /bin/sh "$CHECKOUT/scripts/lint.sh" "$@") \
        > "$TEMP_DIR/output" 2>&1 || actual_status=$?
    if [[ "$actual_status" != "$expected_status" ]]; then
        printf 'Expected exit %s, got %s\n' "$expected_status" "$actual_status" >&2
        exit 1
    fi
}

run_lint 1
grep -q "SwiftLint $VERSION is required" "$TEMP_DIR/output"

cat > "$BIN/swiftlint" <<'STUB'
#!/bin/sh
if [ "$1" = version ]; then
    printf '%s\n' "$FAKE_SWIFTLINT_VERSION"
    exit 0
fi
printf '%s\n' "$PWD" "$@" > "$FAKE_SWIFTLINT_LOG"
exit "$FAKE_SWIFTLINT_STATUS"
STUB
chmod +x "$BIN/swiftlint"
export FAKE_SWIFTLINT_VERSION=0.0.0
export FAKE_SWIFTLINT_LOG="$TEMP_DIR/invocation"
export FAKE_SWIFTLINT_STATUS=0
run_lint 1
grep -q "found 0.0.0" "$TEMP_DIR/output"
[[ ! -e "$FAKE_SWIFTLINT_LOG" ]]

export FAKE_SWIFTLINT_VERSION="$VERSION"
run_lint 0 --strict --reporter json --config 'config with spaces.yml'
# lint.sh runs from the real path; macOS keeps temporary folders behind a symlink.
printf '%s\n' "$(cd "$CHECKOUT" && pwd -P)" lint --strict --reporter json --config 'config with spaces.yml' > "$TEMP_DIR/expected"
cmp "$TEMP_DIR/expected" "$FAKE_SWIFTLINT_LOG"

export FAKE_SWIFTLINT_STATUS=2
run_lint 2
export FAKE_SWIFTLINT_STATUS=0

# The pinned copy from install-swiftlint.sh wins over an older one on PATH.
mkdir -p "$TEMP_DIR/home/.local/bin"
cat > "$TEMP_DIR/home/.local/bin/swiftlint" <<STUB
#!/bin/sh
if [ "\$1" = version ]; then
    printf '%s\n' "$VERSION"
    exit 0
fi
printf 'pinned\n' > "$FAKE_SWIFTLINT_LOG"
STUB
chmod +x "$TEMP_DIR/home/.local/bin/swiftlint"
export FAKE_SWIFTLINT_VERSION=0.0.0
run_lint 0
grep -q pinned "$FAKE_SWIFTLINT_LOG"

printf 'lint wrapper: missing/mismatched versions, pinned copy, arguments, working directory, and exit status passed\n'
