#!/bin/sh
# Runs the test target of every package under packages/, or of the ones named.
#
#   sh scripts/test-packages.sh
#   sh scripts/test-packages.sh ThawLayout ThawCapture
#
# The app's xcodebuild test run does not run a package's own tests, so CI runs
# this next to it. A package without a Tests folder (Fuzzing) is skipped. Every
# package runs even when an earlier one fails, so one run lists all the
# failures; the exit status is non-zero if any package failed.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$ROOT"

if [ "$#" -gt 0 ]; then
    packages="$*"
else
    packages=$(for dir in packages/*/; do
        [ -d "${dir}Tests" ] && basename "$dir"
    done)
fi

failed=""
for name in $packages; do
    if [ ! -d "packages/$name/Tests" ]; then
        echo "error: packages/$name has no Tests folder" >&2
        failed="$failed $name"
        continue
    fi
    # In GitHub Actions each package's log folds into its own group.
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::swift test packages/$name"
    swift test --package-path "packages/$name"
    status=$?
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::"
    if [ "$status" -ne 0 ]; then
        echo "error: tests failed in packages/$name" >&2
        failed="$failed $name"
    fi
done

if [ -n "$failed" ]; then
    echo "Failed packages:$failed" >&2
    exit 1
fi
echo "All package tests passed."
