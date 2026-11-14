#!/bin/sh
# Runs the test target of every package under packages/, or of the ones named.
#
#   sh scripts/test-packages.sh
#   sh scripts/test-packages.sh ThawLayout ThawCapture
#   sh scripts/test-packages.sh --coverage package-coverage
#
# With --coverage DIR each package also records code coverage, and DIR gets one
# <package>.xml per package in the generic format SonarQube reads
# (see package-coverage.py).
#
# The app's xcodebuild test run does not run a package's own tests, so CI runs
# this next to it. A package without a Tests folder (Fuzzing) is skipped. Every
# package runs even when an earlier one fails, so one run lists all the
# failures; the exit status is non-zero if any package failed.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$ROOT"

coverage_dir=""
if [ "${1:-}" = "--coverage" ]; then
    if [ "$#" -lt 2 ]; then
        echo "error: --coverage needs a folder to write the reports to" >&2
        exit 2
    fi
    coverage_dir=$2
    shift 2
    mkdir -p "$coverage_dir"
fi

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
    if [ -n "$coverage_dir" ]; then
        swift test --package-path "packages/$name" --enable-code-coverage
    else
        swift test --package-path "packages/$name"
    fi
    status=$?
    if [ "$status" -eq 0 ] && [ -n "$coverage_dir" ]; then
        codecov=$(swift test --package-path "packages/$name" --show-codecov-path) &&
            python3 scripts/package-coverage.py convert "$codecov" "$coverage_dir/$name.xml" "$ROOT"
        status=$?
    fi
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
