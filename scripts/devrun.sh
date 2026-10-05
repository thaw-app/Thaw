#!/usr/bin/env bash
# Builds Thaw and installs it as /Applications/Thaw Debug.app
# (com.stonerl.Thaw.debug), next to any released Thaw.
# Requires the source checkout at ../PlatformRuntimeKit; builds it directly.
#
# macOS 27 attributes a status item to its app only when the app runs from
# /Applications. Run from DerivedData, Thaw's own icon vanishes on hide.
#
# Full output is saved in a temporary directory outside the checkout.
# Diagnostic logging uses the saved preference, or the build's default.
#
# Usage:
#   ./scripts/devrun.sh                  # Release
#   ./scripts/devrun.sh --debug          # Debug, for the debugger
#   ./scripts/devrun.sh --skip-packages  # skip explicit package resolution
#   ./scripts/devrun.sh --verbose        # stream raw command output too
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
cd "$SCRIPT_DIR/.."

PROJECT="Thaw.xcodeproj"
SCHEME="Thaw"
CONFIG="Release"
APP_NAME="Thaw Debug"
DEST="/Applications/$APP_NAME.app"
BUNDLE_ID="com.stonerl.Thaw.debug"
PROCESS_PATTERN="^${DEST//./\\.}/Contents/MacOS/$APP_NAME( |$)"
SKIP_PACKAGES=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug" ;;
        --release) CONFIG="Release" ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --verbose) VERBOSE=1 ;;
        -h | --help)
            awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$SCRIPT_PATH"
            exit 0
            ;;
        *)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

LOG_ROOT=${TMPDIR:-/tmp}
LOG_DIR=$(mktemp -d "${LOG_ROOT%/}/devrun.XXXXXX")
LOG="$LOG_DIR/build.log"
BUILD_SETTINGS="$LOG_DIR/build-settings.txt"
PID_FILE="$LOG_DIR/app.pid"
: > "$LOG"
# Keep warnings visible while stage output is redirected to the log.
exec 3>&2

printf '%s · %s\nRuntime: ../PlatformRuntimeKit\nLog: %s\n\n' "$APP_NAME" "$CONFIG" "$LOG"
export MENU_BAR_MODEL_PATH="$PWD/MenuBarModel"

# The suffixes rename the app, its XPC service and the controls extension.
BUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    -destination 'platform=macOS'
    -onlyUsePackageVersionsFromResolvedFile
    -skipPackageUpdates
    THAW_BUNDLE_ID_SUFFIX=.debug
    "THAW_PRODUCT_NAME_SUFFIX= Debug"
)

show_failure() {
    local label=$1 status=$2 elapsed=$3 first_line=$4
    printf '\n%s: failed (%ss, exit %s).\n' "$label" "$elapsed" "$status" >&2
    tail -n "+$first_line" "$LOG" > "$LOG_DIR/failure.log"
    if grep -Ei -A 2 'error:|fatal:|BUILD FAILED|Permission denied|No such file|not found' \
        "$LOG_DIR/failure.log" > "$LOG_DIR/diagnostics.txt"; then
        tail -n 20 "$LOG_DIR/diagnostics.txt" >&2
    else
        tail -n 30 "$LOG_DIR/failure.log" >&2
    fi
    printf '\nFull log: %s\n' "$LOG" >&2
}

run_stage() {
    local quiet=0
    if [[ "$1" == --quiet ]]; then quiet=1; shift; fi
    local label=$1 started=$SECONDS status=0 first_line
    local -a pipeline_status
    shift
    if [[ "$quiet" -eq 0 || "$VERBOSE" -eq 1 ]]; then
        printf '%s...\n' "$label"
    fi
    printf '\n== %s ==\n' "$label" >> "$LOG"
    first_line=$(( $(wc -l < "$LOG") + 1 ))
    if [[ "$VERBOSE" -eq 1 ]]; then
        if "$@" 2>&1 | tee -a "$LOG"; then
            status=0
        else
            pipeline_status=("${PIPESTATUS[@]}")
            status=${pipeline_status[0]}
            if [[ "$status" -eq 0 ]]; then status=${pipeline_status[1]}; fi
        fi
    elif "$@" >> "$LOG" 2>&1; then
        status=0
    else
        status=$?
    fi
    if [[ "$status" -ne 0 ]]; then
        show_failure "$label" "$status" "$((SECONDS - started))" "$first_line" || true
        exit "$status"
    fi
    if [[ "$quiet" -eq 0 || "$VERBOSE" -eq 1 ]]; then
        printf '%s: done (%ss).\n' "$label" "$((SECONDS - started))"
    fi
}

check_prerequisites() {
    [[ -f ../PlatformRuntimeKit/Package.swift ]] || {
        printf 'error: local runtime kit not found: %s/PlatformRuntimeKit/Package.swift\n' "$(dirname "$PWD")"
        printf 'Place the PlatformRuntimeKit checkout beside this Thaw checkout.\n'
        return 1
    }
    command -v xcodebuild >/dev/null || {
        printf 'error: xcodebuild not found. Install Xcode and select it with xcode-select.\n'
        return 1
    }
}

build_app() {
    local status=0 products_dir
    # run_stage checks this function's status, so errexit is disabled inside it.
    xcodebuild "${BUILD_ARGS[@]}" build || return $?
    xcodebuild "${BUILD_ARGS[@]}" -showBuildSettings > "$BUILD_SETTINGS" 2>&1 || status=$?
    cat "$BUILD_SETTINGS" || return $?
    [[ "$status" -eq 0 ]] || return "$status"
    products_dir=$(awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}' "$BUILD_SETTINGS")
    [[ -n "$products_dir" && -d "$products_dir/$APP_NAME.app" ]] || {
        printf 'error: build product not found: %s/%s.app\n' "$products_dir" "$APP_NAME"
        return 1
    }
}

quit_running_app() {
    local request_pid
    pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1 || return 0

    # Backgrounded so an app that hangs on quit cannot stall the script.
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" &
    request_pid=$!
    for _ in {1..8}; do
        if ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
            kill "$request_pid" 2>/dev/null || true
            return 0
        fi
        sleep 0.5
    done
    kill "$request_pid" 2>/dev/null || true
    local warning="$APP_NAME did not quit; force-quitting it."
    printf '%s\n' "$warning" >&3
    printf '%s\n' "$warning" >> "$LOG"
    pkill -9 -f "$PROCESS_PATTERN" 2>/dev/null || true
    sleep 1
    if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
        printf 'error: %s is still running; quit it before installing.\n' "$APP_NAME"
        return 1
    fi
}

install_app() {
    rm -rf "$DEST" || return $?
    mv "$APP" "$DEST"
}

launch_app() {
    open "$DEST" || return $?
    for _ in {1..20}; do
        if pgrep -f "$PROCESS_PATTERN" > "$PID_FILE"; then return 0; fi
        sleep 0.25
    done
    printf 'error: launch requested, but no running %s process was found within 5 seconds.\n' "$APP_NAME"
    printf 'Check Console for a crash report, or open %s manually.\n' "$DEST"
    return 1
}

report_logging_preference() {
    local saved state source
    if saved=$(defaults read "$BUNDLE_ID" EnableDiagnosticLogging 2> "$LOG_DIR/preferences.log"); then
        source="saved setting"
        case "$saved" in
            1|true|TRUE|yes|YES) state=on ;;
            0|false|FALSE|no|NO) state=off ;;
            *) state=unknown ;;
        esac
    elif grep -q 'does not exist' "$LOG_DIR/preferences.log"; then
        source="$CONFIG default"
        if [[ "$CONFIG" == Debug ]]; then state=on; else state=off; fi
    else
        state=unknown
        source="could not read saved preference; see log"
    fi
    cat "$LOG_DIR/preferences.log" >> "$LOG"
    printf 'Diagnostic logging: %s (%s).\n' "$state" "$source"
    if [[ "$state" == off ]]; then
        printf 'Enable for the next launch: defaults write %s EnableDiagnosticLogging -bool true\n' "$BUNDLE_ID"
    fi
}

run_stage --quiet 'Check prerequisites' check_prerequisites
if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
    run_stage 'Resolve packages' xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"
else
    printf 'Resolve packages: skipped (--skip-packages).\n'
fi
run_stage Build build_app
PRODUCTS_DIR=$(awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}' "$BUILD_SETTINGS")
APP="$PRODUCTS_DIR/$APP_NAME.app"
if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    run_stage 'Stop previous app' quit_running_app
else
    printf 'Stop previous app: not running.\n'
fi
run_stage Install install_app
run_stage Launch launch_app

printf '\nRunning %s (PID %s).\nApp: %s\n' "$APP_NAME" "$(head -n 1 "$PID_FILE")" "$DEST"
report_logging_preference
printf 'Log: %s\n' "$LOG"
