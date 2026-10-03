#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/checkout with spaces/scripts" "$TEMP_DIR/PlatformRuntimeKit" "$TEMP_DIR/bin"
cp "$ROOT/scripts/thaw-devrun.sh" "$TEMP_DIR/checkout with spaces/scripts/"
touch "$TEMP_DIR/PlatformRuntimeKit/Package.swift"
SCRIPT="$TEMP_DIR/checkout with spaces/scripts/thaw-devrun.sh"

# All commands that could touch the installed app are replaced inside the fixture.
cat > "$TEMP_DIR/bin/fake-command" <<'STUB'
#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_STATE/commands"
case "$name" in
    xcodebuild)
        case " $* " in
            *' -resolvePackageDependencies '*)
                echo 'RAW: package resolution'
                [[ "$SCENARIO" != resolve-failure ]] || { echo 'error: package resolution failed'; exit 67; }
                ;;
            *' -showBuildSettings '*)
                [[ "$SCENARIO" != settings-failure ]] || { echo 'error: build settings unavailable'; exit 68; }
                printf '    BUILT_PRODUCTS_DIR = %s\n' "$TEST_STATE/products"
                ;;
            *' build '*)
                echo 'RAW: compiler output'
                if [[ "$SCENARIO" == build-failure ]]; then
                    echo 'example.swift:7: error: missing argument'
                    # Put the diagnostic beyond a simple last-N-lines fallback.
                    for _ in {1..80}; do echo 'compiler detail'; done
                    exit 65
                fi
                ;;
        esac
        ;;
    pgrep)
        if [[ -f "$TEST_STATE/launched" && "$SCENARIO" != launch-timeout ]]; then
            echo 4242
        elif [[ "$SCENARIO" == stop-existing || "$SCENARIO" == force-stop || "$SCENARIO" == stop-failure ]] &&
            [[ ! -f "$TEST_STATE/stopped" ]]; then
            echo 4111
        else
            exit 1
        fi
        ;;
    open)
        [[ "$SCENARIO" != open-failure ]] || { echo 'error: launch request rejected'; exit 70; }
        touch "$TEST_STATE/launched"
        ;;
    defaults)
        case "$SCENARIO" in
            logging-on) echo 1 ;;
            logging-off) echo 0 ;;
            logging-unknown) echo unexpected ;;
            logging-unreadable) echo 'Failed to read preferences' >&2; exit 1 ;;
            *) echo 'The domain/default pair does not exist' >&2; exit 1 ;;
        esac
        ;;
    tee)
        /usr/bin/tee "$@"
        [[ "$SCENARIO" != log-failure ]] || exit 74
        ;;
    mv)
        [[ "$SCENARIO" != install-failure ]] || { echo 'mv: Permission denied' >&2; exit 69; }
        ;;
    rm)
        [[ "$SCENARIO" != remove-failure ]] || { echo 'rm: Permission denied' >&2; exit 72; }
        ;;
    sleep) /bin/sleep 0.01 ;;
    osascript)
        if [[ "$SCENARIO" == stop-existing ]]; then touch "$TEST_STATE/stopped"; fi
        ;;
    pkill)
        grep -Fq 'Thaw Debug did not quit; force-quitting it.' "$TEST_STATE/stderr" || exit 98
        [[ "$SCENARIO" != stop-failure ]] || exit 1
        touch "$TEST_STATE/stopped"
        ;;
    *) echo "Unexpected command: $name" >&2; exit 99 ;;
esac
STUB
chmod +x "$TEMP_DIR/bin/fake-command"
for command in xcodebuild pgrep open defaults mv rm sleep osascript pkill tee; do
    ln -s fake-command "$TEMP_DIR/bin/$command"
done

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "Missing '$2' in $1"; }
excludes() { if grep -Fq -- "$2" "$1"; then fail "Unexpected '$2' in $1"; fi; }
once() { [[ $(grep -Fc -- "$2" "$1") -eq 1 ]] || fail "Expected '$2' once in $1"; }

run_case() {
    local expected=$1 actual=0
    shift
    TEST_STATE="$TEMP_DIR/$SCENARIO-$RANDOM"
    mkdir -p "$TEST_STATE/products/Thaw Debug.app" "$TEST_STATE/tmp"
    if [[ "$SCENARIO" == missing-product ]]; then rmdir "$TEST_STATE/products/Thaw Debug.app"; fi
    : > "$TEST_STATE/commands"
    env PATH="$TEMP_DIR/bin:$PATH" TMPDIR="$TEST_STATE/tmp/" SCENARIO="$SCENARIO" TEST_STATE="$TEST_STATE" \
        /bin/bash "$SCRIPT" "$@" > "$TEST_STATE/output" 2> "$TEST_STATE/stderr" || actual=$?
    cat "$TEST_STATE/stderr" >> "$TEST_STATE/output"
    [[ "$actual" -eq "$expected" ]] || fail "$SCENARIO: expected exit $expected, got $actual"
    OUTPUT="$TEST_STATE/output"
    COMMANDS="$TEST_STATE/commands"
    LOG=$(awk '/^Log: / { sub(/^Log: /, ""); print; exit }' "$OUTPUT")
    [[ -f "$LOG" ]] || fail "$SCENARIO: no readable log path"
    [[ "$LOG" == "$TEST_STATE/tmp/"* ]] || fail "$SCENARIO: log is not in TMPDIR"
    [[ "$LOG" != *//* ]] || fail "$SCENARIO: duplicate slash in log path"
    excludes "$OUTPUT" $'\033'
}

SCENARIO=logging-on
run_case 0
contains "$OUTPUT" 'Runtime: ../PlatformRuntimeKit'
contains "$OUTPUT" 'Build...'
contains "$OUTPUT" 'Build: done ('
excludes "$OUTPUT" 'Check prerequisites'
contains "$LOG" '== Check prerequisites =='
contains "$OUTPUT" 'Stop previous app: not running.'
excludes "$OUTPUT" 'Stop previous app...'
excludes "$OUTPUT" 'Stop previous app: done'
contains "$OUTPUT" 'Running Thaw Debug (PID 4242).'
contains "$OUTPUT" 'Diagnostic logging: on (saved setting).'
excludes "$OUTPUT" 'RAW:'
contains "$LOG" 'RAW: compiler output'
contains "$LOG" 'RAW: package resolution'
contains "$COMMANDS" 'pgrep -f ^/Applications/Thaw Debug\.app/Contents/MacOS/Thaw Debug( |$)'

SCENARIO=logging-off
run_case 0 --debug --verbose
contains "$OUTPUT" 'RAW: compiler output'
contains "$OUTPUT" 'Check prerequisites: done ('
contains "$OUTPUT" 'Diagnostic logging: off (saved setting).'
contains "$COMMANDS" '-configuration Debug'

SCENARIO=logging-default
run_case 0 --skip-packages
contains "$OUTPUT" 'Resolve packages: skipped (--skip-packages).'
contains "$OUTPUT" 'Diagnostic logging: off (Release default).'
excludes "$COMMANDS" '-resolvePackageDependencies'
run_case 0 --debug
contains "$OUTPUT" 'Diagnostic logging: on (Debug default).'

SCENARIO=logging-unknown
run_case 0
contains "$OUTPUT" 'Diagnostic logging: unknown'
SCENARIO=logging-unreadable
run_case 0
contains "$OUTPUT" 'Diagnostic logging: unknown'
contains "$LOG" 'Failed to read preferences'

SCENARIO=stop-existing
run_case 0
contains "$COMMANDS" 'osascript '
contains "$OUTPUT" 'Stop previous app: done ('
excludes "$OUTPUT" 'force-quitting'
excludes "$COMMANDS" 'pkill '
SCENARIO=force-stop
run_case 0
contains "$COMMANDS" 'pkill -9 -f ^/Applications/Thaw Debug'
once "$OUTPUT" 'Thaw Debug did not quit; force-quitting it.'
once "$LOG" 'Thaw Debug did not quit; force-quitting it.'
run_case 0 --verbose
once "$OUTPUT" 'Thaw Debug did not quit; force-quitting it.'
once "$LOG" 'Thaw Debug did not quit; force-quitting it.'
SCENARIO=stop-failure
run_case 1
contains "$OUTPUT" 'Stop previous app: failed'
excludes "$COMMANDS" 'rm '
excludes "$COMMANDS" 'mv '
excludes "$COMMANDS" 'open '

SCENARIO=build-failure
run_case 65
contains "$OUTPUT" 'Build: failed'
contains "$OUTPUT" 'example.swift:7: error: missing argument'
contains "$LOG" 'compiler detail'
excludes "$COMMANDS" 'mv '
excludes "$COMMANDS" 'open '
excludes "$OUTPUT" 'Running Thaw Debug'
run_case 65 --verbose
contains "$OUTPUT" 'RAW: compiler output'
contains "$OUTPUT" 'Build: failed'
excludes "$COMMANDS" 'mv '

SCENARIO=resolve-failure
run_case 67
contains "$OUTPUT" 'Resolve packages: failed'
excludes "$COMMANDS" '-configuration Release'

SCENARIO=settings-failure
run_case 68
contains "$OUTPUT" 'Build: failed'
contains "$OUTPUT" 'error: build settings unavailable'
excludes "$COMMANDS" 'mv '

SCENARIO=missing-product
run_case 1
contains "$OUTPUT" 'Build: failed'
contains "$OUTPUT" 'build product not found'
excludes "$COMMANDS" 'mv '

SCENARIO=log-failure
run_case 74 --verbose
contains "$OUTPUT" 'Check prerequisites: failed'
excludes "$COMMANDS" 'xcodebuild '

SCENARIO=remove-failure
run_case 72
contains "$OUTPUT" 'Install: failed'
excludes "$COMMANDS" 'mv '
excludes "$COMMANDS" 'open '

SCENARIO=install-failure
run_case 69
contains "$OUTPUT" 'Install: failed'
contains "$OUTPUT" 'Permission denied'
excludes "$COMMANDS" 'open '

SCENARIO=open-failure
run_case 70
contains "$OUTPUT" 'Launch: failed'
excludes "$OUTPUT" 'Running Thaw Debug'

SCENARIO=launch-timeout
run_case 1
contains "$OUTPUT" 'Launch: failed'
contains "$OUTPUT" 'no running Thaw Debug process'
contains "$OUTPUT" 'Check Console for a crash report'
excludes "$OUTPUT" 'Running Thaw Debug'

rm "$TEMP_DIR/PlatformRuntimeKit/Package.swift"
SCENARIO=missing-kit
run_case 1
contains "$OUTPUT" 'Check prerequisites: failed'
contains "$OUTPUT" 'Place the PlatformRuntimeKit checkout beside this Thaw checkout.'
excludes "$COMMANDS" 'xcodebuild '

printf 'thaw-devrun output: all scenarios passed\n'
