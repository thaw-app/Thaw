#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
CHECKOUT="$TEMP_DIR/checkout with spaces"
BIN="$TEMP_DIR/bin"
mkdir -p "$CHECKOUT/scripts" "$BIN"
cp "$ROOT/scripts/format.sh" "$CHECKOUT/scripts/"
cp "$ROOT/.swiftformat-version" "$CHECKOUT/"
ln -s "$(command -v dirname)" "$BIN/dirname"
IFS= read -r VERSION < "$ROOT/.swiftformat-version"

run_format() {
    local expected_status=$1 actual_status=0
    shift
    (cd "$TEMP_DIR" && HOME="$TEMP_DIR/home" PATH="$BIN" /bin/sh "$CHECKOUT/scripts/format.sh" "$@") \
        > "$TEMP_DIR/output" 2>&1 || actual_status=$?
    if [[ "$actual_status" != "$expected_status" ]]; then
        printf 'Expected exit %s, got %s\n' "$expected_status" "$actual_status" >&2
        exit 1
    fi
}

run_format 1
grep -q "SwiftFormat $VERSION is required" "$TEMP_DIR/output"

cat > "$BIN/swiftformat" <<'STUB'
#!/bin/sh
if [ "$1" = --version ]; then
    printf '%s\n' "$FAKE_SWIFTFORMAT_VERSION"
    exit 0
fi
printf '%s\n' "$PWD" "$@" > "$FAKE_SWIFTFORMAT_LOG"
exit "$FAKE_SWIFTFORMAT_STATUS"
STUB
chmod +x "$BIN/swiftformat"
export FAKE_SWIFTFORMAT_VERSION=0.0.0
export FAKE_SWIFTFORMAT_LOG="$TEMP_DIR/invocation"
export FAKE_SWIFTFORMAT_STATUS=0
run_format 1
grep -q "found 0.0.0" "$TEMP_DIR/output"
[[ ! -e "$FAKE_SWIFTFORMAT_LOG" ]]

export FAKE_SWIFTFORMAT_VERSION="$VERSION"
run_format 0 --lint --config 'config with spaces'
printf '%s\n' "$CHECKOUT" . --lint --config 'config with spaces' > "$TEMP_DIR/expected"
cmp "$TEMP_DIR/expected" "$FAKE_SWIFTFORMAT_LOG"

export FAKE_SWIFTFORMAT_STATUS=2
run_format 2
export FAKE_SWIFTFORMAT_STATUS=0

# The pinned copy from install-swiftformat.sh wins over an older one on PATH.
mkdir -p "$TEMP_DIR/home/.local/bin"
cat > "$TEMP_DIR/home/.local/bin/swiftformat" <<STUB
#!/bin/sh
if [ "\$1" = --version ]; then
    printf '%s\n' "$VERSION"
    exit 0
fi
printf 'pinned\n' > "$FAKE_SWIFTFORMAT_LOG"
STUB
chmod +x "$TEMP_DIR/home/.local/bin/swiftformat"
export FAKE_SWIFTFORMAT_VERSION=0.0.0
run_format 0
grep -q pinned "$FAKE_SWIFTFORMAT_LOG"

printf 'format wrapper: missing/mismatched versions, pinned copy, arguments, working directory, and exit status passed\n'
