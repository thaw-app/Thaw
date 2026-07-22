#!/usr/bin/env bash
#
# thaw-devrun.sh — Build the Debug config and run it from /Applications so the
# macOS 27 menu-bar hiding feature works with a local build.
#
# Why this exists: on macOS 27 a status item's menu-bar scene is only attributed
# to its app when the app has a clean code identity AND a canonical /Applications
# location. A Debug build run straight from DerivedData/Xcode hosts its status
# item as `nil`, so the visibility-restriction allowlist can't protect it and
# Thaw's own icon vanishes whenever anything is hidden.
#
# The Debug configuration uses bundle id `com.stonerl.Thaw.debug` (cleanly owned
# by the building developer's own team — no conflict with the Developer-ID
# `com.stonerl.Thaw`, which only the release signer can use). This script builds
# it, quits any running 'Thaw Debug' (the app AND its XPC service), deletes the
# old `/Applications/Thaw Debug.app`, installs the fresh build, and launches it —
# no manual quitting or trashing needed, no Developer-ID cert and no release.
#
# Usage:
#   ./scripts/thaw-devrun.sh
#   ./scripts/thaw-devrun.sh --skip-packages
#
# The development workspace can override the public `prk-bin` dependency with a
# sibling `../PlatformRuntimeKit` checkout via a source mirror under
# `.swiftpm-overrides/`. When that sibling is missing, this script builds with
# `Thaw.xcodeproj` and the published packages as-is.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="Thaw"
CONFIG="Debug"
DEST="/Applications/Thaw Debug.app"
DEBUG_BUNDLE_ID="com.stonerl.Thaw.debug"
WORKSPACE="ThawDev.xcworkspace"
PROJECT="Thaw.xcodeproj"
PRK_SOURCE="../PlatformRuntimeKit"
PRK_OVERRIDE_DIR=".swiftpm-overrides"
PRK_OVERRIDE="$PRK_OVERRIDE_DIR/prk-bin"
USE_LOCAL_PRK=0
export MENU_BAR_MODEL_PATH="$PWD/MenuBarModel"
PACKAGE_RESOLUTION_ARGS=(-onlyUsePackageVersionsFromResolvedFile)

SKIP_PACKAGES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-packages)
            SKIP_PACKAGES=1
            shift
            ;;
        -h | --help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2
            ;;
    esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

prepare_local_package_override() {
    # Mirror sibling PlatformRuntimeKit into a directory literally named
    # `prk-bin`. Xcode 27 resolves symlinks before computing package identity,
    # so a `prk-bin -> PlatformRuntimeKit` symlink has identity
    # `platformruntimekit` and fails to override the published `prk-bin`
    # dependency. The gitignored source mirror preserves the required identity
    # while still including uncommitted local kit work.
    if [[ -f "$PRK_SOURCE/Package.swift" ]]; then
        mkdir -p "$PRK_OVERRIDE_DIR"
        rm -rf "$PRK_OVERRIDE"
        mkdir -p "$PRK_OVERRIDE"
        rsync -a --delete \
            --exclude .build \
            --exclude .git \
            "$PRK_SOURCE/" "$PRK_OVERRIDE/"
        USE_LOCAL_PRK=1
        say "Using local PlatformRuntimeKit ($PRK_SOURCE)"
    else
        USE_LOCAL_PRK=0
        if [[ -e "$PRK_OVERRIDE" || -L "$PRK_OVERRIDE" ]]; then
            rm -rf "$PRK_OVERRIDE"
        fi
        say "No local PlatformRuntimeKit at $PRK_SOURCE — using published prk-bin"
    fi
}

resolve_swift_packages() {
    say "Resolving Swift packages…"
    xcodebuild -resolvePackageDependencies \
        "${XCODE_ROOT_ARGS[@]}" \
        -scheme "$SCHEME" \
        "${PACKAGE_RESOLUTION_ARGS[@]}"
}

prepare_local_package_override
if [[ "$USE_LOCAL_PRK" -eq 1 ]]; then
    XCODE_ROOT_ARGS=(-workspace "$WORKSPACE")
    # Keep ThawDev Package.resolved aligned with the project remotes before a
    # pinned resolve; the workspace file historically lagged prk-bin / AX pins.
    cp -f \
        "Thaw.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
        "ThawDev.xcworkspace/xcshareddata/swiftpm/Package.resolved"
else
    XCODE_ROOT_ARGS=(-project "$PROJECT")
fi
if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
    resolve_swift_packages
fi

# Quit every running 'Thaw Debug' process — the app AND its MenuBarItemService
# XPC child — without touching a release `Thaw`. Matches on the install path so
# it's precise. Tries a graceful quit first (clean assertion teardown), then
# force-kills anything still alive. The hiding assertion auto-releases on exit,
# so a force-kill leaves no lingering restriction.
quit_thaw_debug() {
    pgrep -f "$DEST/" >/dev/null 2>&1 || return 0

    say "Quitting running 'Thaw Debug'…"
    # Backgrounded so a macOS 27 quit-hang can't stall the script.
    ( osascript -e "tell application id \"$DEBUG_BUNDLE_ID\" to quit" >/dev/null 2>&1 ) &

    # Poll up to ~4s for the app + XPC service to exit on their own.
    for _ in {1..8}; do
        pgrep -f "$DEST/" >/dev/null 2>&1 || return 0
        sleep 0.5
    done

    say "Force-killing leftover 'Thaw Debug' processes…"
    pkill -9 -f "$DEST/" 2>/dev/null || true
    sleep 1
}

say "Building ${CONFIG}…"
xcodebuild "${XCODE_ROOT_ARGS[@]}" -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination 'platform=macOS' "${PACKAGE_RESOLUTION_ARGS[@]}" build

PRODUCTS_DIR=$(xcodebuild "${XCODE_ROOT_ARGS[@]}" -scheme "$SCHEME" -configuration "$CONFIG" \
    "${PACKAGE_RESOLUTION_ARGS[@]}" -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP="${PRODUCTS_DIR}/Thaw.app"
[ -d "$APP" ] || { echo "Build product not found: $APP"; exit 1; }

quit_thaw_debug

if [ -e "$DEST" ]; then
    say "Removing existing ${DEST}…"
    rm -rf "$DEST"
fi

say "Installing to ${DEST}…"
mv "$APP" "$DEST"

say "Launching…"
# Match the Thaw scheme's LaunchAction env so malloc stack traces work outside Xcode.
# open --env MallocStackLogging=1 "$DEST"
open "$DEST"
say "Running 'Thaw Debug'. First launch: grant Accessibility + Screen Recording."
