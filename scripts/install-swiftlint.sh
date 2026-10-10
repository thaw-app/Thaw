#!/bin/sh
set -eu

# Installs the SwiftLint version pinned in .swiftlint-version from the
# official release artifact bundle, for CI runners that run xcodebuild
# and therefore the project's lint build phase.

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IFS= read -r VERSION < "$ROOT/.swiftlint-version"
TARGET=${1:-"$HOME/.local/bin"}

[ "$(uname -s)" = Darwin ] || {
    echo "error: this installer supports macOS runners; download manually on $(uname -s)." >&2
    exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 -o "$TMP/bundle.zip" \
    "https://github.com/realm/SwiftLint/releases/download/$VERSION/SwiftLintBinary.artifactbundle.zip"
unzip -q "$TMP/bundle.zip" -d "$TMP"

mkdir -p "$TARGET"
install -m 0755 "$TMP/SwiftLintBinary.artifactbundle/macos/swiftlint" "$TARGET/swiftlint"
INSTALLED=$("$TARGET/swiftlint" version)
[ "$INSTALLED" = "$VERSION" ] || {
    echo "error: installed SwiftLint $INSTALLED does not match the pinned $VERSION." >&2
    exit 1
}
echo "SwiftLint $INSTALLED installed in $TARGET"
