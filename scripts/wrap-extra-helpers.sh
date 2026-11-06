#!/bin/zsh
# Xcode build phase: wraps the embedded ThawExtraHelper executable into one
# .app per Apple menu extra and per third-party stand-in slot, then removes the
# bare copy. Each bundle needs its own identifier, because macOS 27 conceals
# status items per bundle.
set -euo pipefail
extras="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/Extras"
exe="$extras/ThawExtraHelper"
[[ -f $exe ]] || { echo "warning: wrap-extra-helpers: $exe not found"; exit 0; }
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
for role in focus timemachine timer airdrop nowplaying user textinput slot1 slot2 slot3 slot4 slot5 slot6; do
    "${SRCROOT}/scripts/assemble-extra-helper.sh" "$exe" "$extras" "${PRODUCT_BUNDLE_IDENTIFIER}" "$role" "$identity"
done
rm -f "$exe"
