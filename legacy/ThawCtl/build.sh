#!/bin/bash
set -euo pipefail

SWIFT=${SWIFT:-swift}
PRODUCT="ThawCtl"
CONFIGURATION=${CONFIGURATION:-debug}

if [ "$CONFIGURATION" = "release" ]; then
    BUILD_FLAG="-c release"
else
    BUILD_FLAG=""
fi

echo "Building $PRODUCT..."
cd "$(dirname "$0")"
$SWIFT build $BUILD_FLAG

BINARY=".build/${CONFIGURATION}/${PRODUCT}"
APP_BUNDLE=".build/${CONFIGURATION}/${PRODUCT}.app"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign so macOS accepts the URL scheme registration
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null

echo "✅ $APP_BUNDLE"
echo ""
echo "Run: open \"$APP_BUNDLE\""
echo "Then send commands from the UI to test Thaw automation."
