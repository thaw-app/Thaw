#!/usr/bin/env bash
# Regenerates scripts/swiftlint-inputs.xcfilelist from tracked Swift sources
# in the same modules SwiftLint lints (see .swiftlint.yml).
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
output="${1:-$root/scripts/swiftlint-inputs.xcfilelist}"

cd "$root"

# LC_ALL=C keeps the ordering byte-wise so the list is identical on macOS and
# on the Linux CI runner; locale collation would otherwise reorder entries that
# differ only in case and fail the verification step.
git ls-files '*.swift' \
    | grep -E '^(MenuBarCaptureService|MenuBarItemService|Shared|Thaw)/' \
    | LC_ALL=C sort \
    | sed 's|^|$(SRCROOT)/|' \
    > "$output"
