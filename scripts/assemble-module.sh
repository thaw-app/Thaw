#!/bin/zsh
# Wraps a module executable into the .app that ModuleHost launches.
# Usage: assemble-module.sh <executable> <output dir> <parent bundle id> <module id> <name> <version> [signing identity]
set -euo pipefail
exe=$1 out=$2 parent=$3 module=$4 name=$5 version=$6 identity=${7:--}
app="$out/$name.app"
executable=${exe:t}
bundle="$parent.module.$module"
# Thaw answers a module's requests on a scheme named after its bundle ID, so
# a debug and a release copy of the same module never receive each other's replies.
scheme=${bundle:l}
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$exe" "$app/Contents/MacOS/$executable"
# A module shares the frameworks Xcode puts in Thaw's own Frameworks folder,
# five levels up from its executable, and has no rpath of its own to find them.
hostFrameworks="@executable_path/../../../../../Frameworks"
otool -l "$app/Contents/MacOS/$executable" | grep -q "path $hostFrameworks " ||
    install_name_tool -add_rpath "$hostFrameworks" "$app/Contents/MacOS/$executable"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$executable</string>
  <key>CFBundleIdentifier</key><string>$bundle</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>$bundle</string>
      <key>CFBundleURLSchemes</key><array><string>$scheme</string></array>
    </dict>
  </array>
  <key>LSUIElement</key><true/>
  <key>ThawModuleIdentifier</key><string>$module</string>
  <key>ThawModuleMinimumAPIVersion</key><integer>1</integer>
</dict>
</plist>
PLIST
# Ad-hoc signatures cannot carry a secure timestamp; real ones need one to notarize.
timestamp=--timestamp
[[ $identity == - ]] && timestamp=--timestamp=none
codesign --force --sign "$identity" --options runtime $timestamp "$app"
echo "$app"
