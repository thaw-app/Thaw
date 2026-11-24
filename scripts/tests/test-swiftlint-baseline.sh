#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
SCRIPT="$ROOT/scripts/swiftlint-baseline.py"

entry() {
    printf '{"text":"%s","violation":{"ruleIdentifier":"%s","reason":"currently spans %s lines","location":{"file":"A.swift","line":%s}}}' "$1" "$2" "$3" "$4"
}

printf '[%s,%s]' "$(entry 'func a() {' function_body_length 60 10)" "$(entry 'struct A {' type_body_length 400 1)" > "$TEMP_DIR/old.json"

expect() {
    local expected_status=$1 actual_status=0
    shift
    python3 "$SCRIPT" "$@" > "$TEMP_DIR/output" 2>&1 || actual_status=$?
    if [[ "$actual_status" != "$expected_status" ]]; then
        printf 'Expected exit %s, got %s from %s\n' "$expected_status" "$actual_status" "$*" >&2
        cat "$TEMP_DIR/output" >&2
        exit 1
    fi
}

# Shrinking, moving and dropping entries pass.
printf '[%s]' "$(entry 'func a() {' function_body_length 55 30)" > "$TEMP_DIR/smaller.json"
expect 0 check "$TEMP_DIR/old.json" "$TEMP_DIR/smaller.json"

printf '[%s,%s]' "$(entry 'func a() {' function_body_length 61 10)" "$(entry 'struct A {' type_body_length 400 1)" > "$TEMP_DIR/larger.json"
expect 1 check "$TEMP_DIR/old.json" "$TEMP_DIR/larger.json"
grep -q 'grew from 60 to 61' "$TEMP_DIR/output"

printf '[%s]' "$(entry 'func b() {' function_body_length 51 10)" > "$TEMP_DIR/new.json"
expect 1 check "$TEMP_DIR/old.json" "$TEMP_DIR/new.json"
grep -q 'is new' "$TEMP_DIR/output"

printf '[%s]' "$(entry 'x' line_length 200 3)" > "$TEMP_DIR/other-rule.json"
expect 1 check "$TEMP_DIR/old.json" "$TEMP_DIR/other-rule.json"
grep -q "line_length can't be baselined" "$TEMP_DIR/output"

# update writes only when the fresh baseline shrinks.
cp "$TEMP_DIR/old.json" "$TEMP_DIR/current.json"
expect 1 update "$TEMP_DIR/current.json" "$TEMP_DIR/larger.json"
cmp -s "$TEMP_DIR/old.json" "$TEMP_DIR/current.json"
expect 0 update "$TEMP_DIR/current.json" "$TEMP_DIR/smaller.json"
grep -q '"currently spans 55 lines"' "$TEMP_DIR/current.json"

# update keeps an unchanged entry's old line number while shrunk entries take the fresh one.
printf '[%s,%s]' "$(entry 'func a() {' function_body_length 60 10)" "$(entry 'struct A {' type_body_length 400 1)" > "$TEMP_DIR/old.json"
printf '[%s,%s]' "$(entry 'func a() {' function_body_length 58 40)" "$(entry 'struct A {' type_body_length 400 25)" > "$TEMP_DIR/renumbered.json"
cp "$TEMP_DIR/old.json" "$TEMP_DIR/current.json"
expect 0 update "$TEMP_DIR/current.json" "$TEMP_DIR/renumbered.json"
grep -q '"line": 1$' "$TEMP_DIR/current.json"
grep -q '"line": 40$' "$TEMP_DIR/current.json"
if grep -q '"line": 25$' "$TEMP_DIR/current.json"; then
    printf 'Unchanged entry took the fresh line\n' >&2
    exit 1
fi

# An entry that keeps its line is never taken by another fresh entry with the same text and size.
printf '[%s,%s]' "$(entry 'func a() {' function_body_length 60 10)" "$(entry 'func a() {' function_body_length 58 100)" > "$TEMP_DIR/old.json"
printf '[%s,%s]' "$(entry 'func a() {' function_body_length 58 10)" "$(entry 'func a() {' function_body_length 58 100)" > "$TEMP_DIR/same-text.json"
cp "$TEMP_DIR/old.json" "$TEMP_DIR/current.json"
expect 0 update "$TEMP_DIR/current.json" "$TEMP_DIR/same-text.json"
grep -q '"line": 10$' "$TEMP_DIR/current.json"
grep -q '"line": 100$' "$TEMP_DIR/current.json"

printf 'swiftlint baseline: shrinking, growth, new entries, other rules, update and unchanged entries passed\n'
