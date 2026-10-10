#!/usr/bin/env python3
"""Report local code coverage using the same denominator SonarCloud uses.

Usage:
    scripts/coverage-report.py [xcresult-path] [--top N] [--json]

Reads an .xcresult bundle with `xcrun xccov`, then applies `sonar.sources` and
`sonar.coverage.exclusions` from sonar-project.properties so the number printed
here is comparable to the one on SonarCloud.

Without the exclusions the raw xccov figure is far lower (it counts every
SwiftUI view and WindowServer wrapper in the app), which makes it useless as a
progress gauge against a Sonar target. Coverage measured on the excluded set is
what the quality gate reports.

xcresult-path defaults to the newest bundle under Build/Logs/Test.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROPERTIES = REPO_ROOT / "sonar-project.properties"


def read_property(name: str) -> list[str]:
    """Return the comma-separated values of a (possibly line-continued) key."""
    text = PROPERTIES.read_text(encoding="utf-8")
    # Join backslash continuations so multi-line lists parse as one value.
    text = text.replace("\\\n", " ")
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#") or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        if key.strip() == name:
            return [v.strip() for v in value.split(",") if v.strip()]
    return []


def is_excluded(path: str, patterns: list[str]) -> bool:
    """Match a repo-relative path against Sonar's glob syntax."""
    for pattern in patterns:
        # Sonar treats a bare `dir/*.swift` as non-recursive and `**` as
        # recursive; fnmatch's `*` crosses `/`, so match those patterns by
        # hand and only accept files directly beneath the directory.
        if pattern.endswith("/*.swift") and "**" not in pattern:
            prefix = pattern[: -len("*.swift")]
            if (path.startswith(prefix)
                    and path.endswith(".swift")
                    and "/" not in path[len(prefix):]):
                return True
        elif fnmatch.fnmatch(path, pattern):
            return True
    return False


def newest_xcresult() -> Path:
    candidates = sorted(
        (REPO_ROOT / "Build" / "Logs" / "Test").glob("*.xcresult"),
        key=lambda p: p.stat().st_mtime,
    )
    if not candidates:
        sys.exit(
            "error: no .xcresult under Build/Logs/Test -- run the test suite first:\n"
            "  xcodebuild test -project Thaw.xcodeproj -scheme Thaw "
            "-destination 'platform=macOS' -derivedDataPath Build/ -enableCodeCoverage YES"
        )
    return candidates[-1]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "xcresult_path",
        nargs="?",
        type=Path,
        default=None,
        help="path to the .xcresult bundle (default: newest under Build/Logs/Test)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=30,
        help="number of files to list in the text report (default: 30)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="emit JSON instead of the text report",
    )
    return parser.parse_args(argv[1:])


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    top = args.top
    as_json = args.as_json

    bundle = args.xcresult_path if args.xcresult_path else newest_xcresult()

    raw = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", str(bundle)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    report = json.loads(raw)

    sources = tuple(s.rstrip("/") + "/" for s in read_property("sonar.sources"))
    exclusions = read_property("sonar.coverage.exclusions")
    if not sources:
        sys.exit("error: sonar.sources missing from sonar-project.properties")

    # Files under Shared/ are compiled into both the app and the XPC service, so
    # xccov reports them once per target. Sonar counts each source file once, so
    # keep the best result per path -- a line covered by either target is covered.
    best: dict[str, dict] = {}
    excluded_files = 0
    for target in report.get("targets", []):
        for entry in target.get("files", []):
            path = entry["path"]
            # xccov reports absolute paths; make them repo-relative.
            marker = str(REPO_ROOT) + "/"
            path = path[len(marker):] if path.startswith(marker) else path
            if not path.startswith(sources):
                continue
            if is_excluded(path, exclusions):
                excluded_files += 1
                continue
            lines = entry["executableLines"]
            covered = entry["coveredLines"]
            previous = best.get(path)
            if previous is None or covered > previous["covered"]:
                best[path] = {
                    "path": path,
                    "lines": lines,
                    "covered": covered,
                    "uncovered": lines - covered,
                    "coverage": round(100 * covered / lines, 1) if lines else 100.0,
                }

    rows = list(best.values())
    total_lines = sum(r["lines"] for r in rows)
    total_covered = sum(r["covered"] for r in rows)

    if not total_lines:
        sys.exit("error: no measurable lines found -- check sonar.sources vs xccov paths")

    coverage = 100 * total_covered / total_lines
    rows.sort(key=lambda r: r["uncovered"], reverse=True)

    if as_json:
        print(json.dumps({"coverage": coverage, "files": rows}, indent=2))
        return 0

    # 90% is the project target; report the gap in lines, which is the unit
    # the work is actually done in.
    to_ninety = max(0, (total_lines - total_covered) - int(0.10 * total_lines))
    print(f"bundle:   {bundle.name}")
    print(f"files:    {len(rows)} measured, {excluded_files} excluded by sonar")
    print(f"lines:    {total_lines} measurable, {total_covered} covered, "
          f"{total_lines - total_covered} uncovered")
    print(f"COVERAGE: {coverage:.2f}%")
    print(f"to 90%:   cover {to_ninety} more lines")
    print()
    print(f"{'uncov':>6} {'cov%':>7} {'lines':>6}  path")
    for row in rows[:top]:
        print(f"{row['uncovered']:>6} {row['coverage']:>7} {row['lines']:>6}  {row['path']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
