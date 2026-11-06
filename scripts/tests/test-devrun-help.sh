#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/devrun.sh"
EXPECTED=$(/bin/bash "$SCRIPT" --help)
[[ "$EXPECTED" == *"Usage:"* ]] || exit 1

check_help() {
    local actual
    actual=$(cd "$1" && /bin/bash "$2" --help) || {
        printf 'Help failed from %s using %s\n' "$1" "$2" >&2
        exit 1
    }
    [[ "$actual" == "$EXPECTED" ]] || {
        printf 'Help output differs from %s using %s\n' "$1" "$2" >&2
        exit 1
    }
}

check_help "$ROOT" ./scripts/devrun.sh
check_help "$ROOT/scripts" ./devrun.sh
check_help /tmp "$SCRIPT"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/checkout with spaces/scripts"
cp "$SCRIPT" "$TEMP_DIR/checkout with spaces/scripts/"
check_help "$TEMP_DIR/checkout with spaces/scripts" ./devrun.sh

printf 'devrun --help: all invocation paths passed\n'
