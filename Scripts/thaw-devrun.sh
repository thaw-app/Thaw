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
# it, installs it to `/Applications/Thaw Debug.app`, and launches it — no
# Developer-ID cert and no release required.
#
# Usage: Scripts/thaw-devrun.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="Thaw"
CONFIG="Debug"
DEST="/Applications/Thaw Debug.app"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

say "Building ${CONFIG}…"
xcodebuild -project Thaw.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination 'platform=macOS' build >/dev/null

PRODUCTS_DIR=$(xcodebuild -project Thaw.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP="${PRODUCTS_DIR}/Thaw.app"
[ -d "$APP" ] || { echo "Build product not found: $APP"; exit 1; }

say "Installing to ${DEST}…"
pkill -9 -x Thaw 2>/dev/null || true
sleep 1
rm -rf "$DEST"
mv "$APP" "$DEST"

say "Launching…"
open "$DEST"
say "Running 'Thaw Debug'. First launch: grant Accessibility + Screen Recording."
