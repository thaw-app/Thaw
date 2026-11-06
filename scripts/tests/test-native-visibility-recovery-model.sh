#!/bin/bash
# Runs the real recovery model tests without launching Thaw or its hiding engines.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d "${TMPDIR:-/tmp}/thaw-recovery-model.XXXXXX")
trap 'rm -rf "$work"' EXIT

developer=$(xcode-select -p)
frameworks="$developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
plugin="$developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
printf '%s\n' \
  'import Darwin' \
  'import Testing' \
  '@main struct RecoveryModelTestsMain {' \
  '    static func main() async { let code: CInt = await Testing.__swiftPMEntryPoint(); exit(code) }' \
  '}' > "$work/main.swift"

xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos14.0" \
  -DRECOVERY_STANDALONE -parse-as-library \
  -load-plugin-library "$plugin" \
  -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
  Thaw/Settings/Models/NativeVisibilityRecoveryModel.swift \
  ThawTests/Settings/NativeVisibilityRecoveryModelTests.swift \
  "$work/main.swift" -o "$work/tests"
"$work/tests"
