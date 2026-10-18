#!/bin/zsh
# Xcode build phase: wraps each embedded module executable into its .app in
# Contents/Library/Modules, then removes the bare copy. ModuleHost launches
# these bundled copies when no downloaded copy exists.
set -euo pipefail
moduleDir="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/Modules"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
# Every app is rebuilt below from its executable, so an app left by an
# earlier build, such as one under a name a module no longer has, goes first.
rm -rf "$moduleDir"/*.app(N)
# executable, module identifier, app name
for spec in "ThawAutomation automation Thaw Scripts" "ThawTriggers triggers Thaw Triggers" "ThawWidgets widgets Thaw Widgets"; do
    parts=(${=spec})
    exe="$moduleDir/${parts[1]}"
    [[ -f $exe ]] || { echo "warning: wrap-modules: $exe not found"; continue; }
    "${SRCROOT}/scripts/assemble-module.sh" "$exe" "$moduleDir" "${PRODUCT_BUNDLE_IDENTIFIER}" "${parts[2]}" "${parts[3,-1]}" "${MARKETING_VERSION:-1.0}" "$identity"
    rm -f "$exe"
done
