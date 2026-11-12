#!/bin/sh
set -eu

# Installs the SwiftFormat version pinned in .swiftformat-version from the
# official release, so local runs and CI format the same way.

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IFS= read -r VERSION < "$ROOT/.swiftformat-version"
TARGET=${1:-"$HOME/.local/bin"}

case "$(uname -s)/$(uname -m)" in
    Darwin/*) ASSET=swiftformat.zip BINARY=swiftformat ;;
    Linux/x86_64) ASSET=swiftformat_linux.zip BINARY=swiftformat_linux ;;
    Linux/aarch64) ASSET=swiftformat_linux_aarch64.zip BINARY=swiftformat_linux_aarch64 ;;
    *)
        echo "error: no SwiftFormat release for $(uname -s) $(uname -m)." >&2
        exit 1
        ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 -o "$TMP/swiftformat.zip" \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$VERSION/$ASSET"
unzip -q "$TMP/swiftformat.zip" -d "$TMP"

mkdir -p "$TARGET"
install -m 0755 "$TMP/$BINARY" "$TARGET/swiftformat"
INSTALLED=$("$TARGET/swiftformat" --version)
[ "$INSTALLED" = "$VERSION" ] || {
    echo "error: installed SwiftFormat $INSTALLED does not match the pinned $VERSION." >&2
    exit 1
}
echo "SwiftFormat $INSTALLED installed in $TARGET"
