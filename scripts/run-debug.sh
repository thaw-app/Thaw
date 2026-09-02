#!/usr/bin/env bash
# Build Debug Thaw with the stable local codesign identity and launch it.
# Run scripts/setup-local-codesign.sh once first.
set -euo pipefail

NAME="Thaw Local Codesign"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"${NAME}\"" >/dev/null; then
  echo "Local codesign identity missing. Running setup…"
  bash "${ROOT}/scripts/setup-local-codesign.sh"
fi

DERIVED="${DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData/Thaw-local}"
APP="${DERIVED}/Build/Products/Debug/Thaw.app"

echo "Building with identity: ${NAME}"
# Self-signed local identity cannot satisfy Hardened Runtime entitlement
# checks; keep this Debug-only helper off Hardened Runtime on purpose.
xcodebuild \
  -scheme Thaw \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${NAME}" \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  OTHER_CODE_SIGN_FLAGS=--timestamp=none \
  build

# Ensure nested XPC is signed with the same identity (Manual style can miss it).
if [[ -d "${APP}/Contents/XPCServices" ]]; then
  find "${APP}/Contents/XPCServices" -name '*.xpc' -print0 2>/dev/null \
    | while IFS= read -r -d '' xpc; do
      codesign --force --sign "${NAME}" --timestamp=none --deep "${xpc}" || true
    done
fi
codesign --force --sign "${NAME}" --timestamp=none --deep "${APP}"

echo "Codesign verify:"
codesign -dv --verbose=2 "${APP}" 2>&1 | rg -i "Authority|Identifier|Signature|TeamIdentifier|Format" || true

pkill -x Thaw 2>/dev/null || true
sleep 0.4
open "${APP}"
sleep 1
pgrep -lf "Thaw.app/Contents/MacOS/Thaw" | head -3 || true
echo "Launched: ${APP}"
