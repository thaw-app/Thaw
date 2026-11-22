#!/usr/bin/env bash
# Runs the installed Thaw Debug through its resident memory benchmark on the live menu bar and prints
# the footprint at each stage. Exits 1 when a stage is over its budget or the run did not finish.
# The stages and budgets are in Thaw/App/ResidentBench.swift.
#
# Usage:
#   ./scripts/bench-resident.sh
set -euo pipefail

APP_NAME="Thaw Debug"
APP="/Applications/$APP_NAME.app"
BUNDLE_ID="com.stonerl.Thaw.debug"
PROCESS_PATTERN="^${APP//./\\.}/Contents/MacOS/$APP_NAME( |$)"
# A run takes about three minutes; a first scan that never settles gives up after two.
TIMEOUT_SECONDS=420

if [[ ! -d "$APP" ]]; then
    echo "error: $APP is not installed. Build and install it with ./scripts/devrun.sh first." >&2
    exit 1
fi
# The benchmark measures a fresh launch, and a second copy would only hand over to the first.
if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    echo "error: $APP_NAME is running. Quit it, then run this again." >&2
    exit 1
fi

log=$(mktemp -t thaw-bench-resident)
watchdog=""
cleanup() {
    [[ -n "$watchdog" ]] && kill "$watchdog" 2>/dev/null
    rm -f "$log"
}
trap cleanup EXIT

echo "Running $APP_NAME's resident memory benchmark on the live menu bar. This takes about three minutes."
# Launched through LaunchServices so the app, not this terminal, holds its own permissions.
open -W -n -a "$APP" --stdout "$log" --args --bench-resident &
opener=$!
# A hung run is asked to quit the normal way, so Thaw's own quit work still runs.
(
    sleep "$TIMEOUT_SECONDS"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
) &
watchdog=$!
wait "$opener" || true

printf '%-16s %10s %8s  %s\n' "Stage" "MiB" "Budget" "Result"
awk '
    $1 == "RESIDENT" && $4 == "MiB" { printf "%-16s %10s %8s  %s\n", $2, $3, $6, ($3 > $6 ? "over" : "ok") }
    $1 == "RESIDENT" && $3 == "unreadable" { printf "%-16s %10s %8s  %s\n", $2, "?", $5, "unreadable" }
' "$log"

verdict=$(grep -E '^RESIDENT (PASS|FAIL)' "$log" | tail -n 1 || true)
if [[ -z "$verdict" ]]; then
    echo "error: the benchmark did not finish within $TIMEOUT_SECONDS seconds or $APP_NAME quit early." >&2
    tail -n 5 "$log" >&2
    exit 1
fi
echo "${verdict#RESIDENT }"
[[ "$verdict" == "RESIDENT PASS" ]]
