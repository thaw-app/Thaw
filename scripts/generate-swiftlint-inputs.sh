#!/usr/bin/env bash
# Regenerates scripts/swiftlint-inputs.xcfilelist from tracked Swift sources
# in the same modules SwiftLint lints (see .swiftlint.yml).
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
output="${1:-$root/scripts/swiftlint-inputs.xcfilelist}"

cd "$root"

git ls-files '*.swift' \
    | grep -E '^(MenuBarItemService|Shared|Thaw)/' \
    | sort \
    | sed 's|^|$(SRCROOT)/|' \
    > "$output"
