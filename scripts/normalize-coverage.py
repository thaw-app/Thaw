#!/usr/bin/env python3
"""Rewrite xcresultparser coverage paths so SonarQube can resolve them.

Usage:
    scripts/normalize-coverage.py coverage.xml [workspace-root]

xcresultparser emits absolute paths from the macOS runner
(/Users/runner/work/Thaw/Thaw/...), but the Sonar scan runs on a Linux runner
with a different workspace root. Sonar matches coverage entries against source
files by path, so every entry silently fails to resolve and the project lands
at 0% coverage -- both overall and on new code.

This rewrites every <file path="..."> to a repo-relative path and drops entries
that live outside the repo (DerivedData, SPM checkouts), which Sonar has no
sources for. The file is edited in place.

workspace-root defaults to $GITHUB_WORKSPACE, then to the repo root inferred
from this script's location.
"""

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Path segments that mark a build artifact rather than a repo source file.
# xcresultparser reports coverage for SPM dependencies compiled into the test
# host; those are not in sonar.sources and only add noise.
ARTIFACT_MARKERS = ("/Build/", "/DerivedData/", "/.build/", "/SourcePackages/")


def repo_relative(path: str, roots: list[str]) -> str | None:
    """Return `path` relative to the first matching root, or None to drop it."""
    if any(marker in path for marker in ARTIFACT_MARKERS):
        return None
    if not path.startswith("/"):
        return path  # already relative
    for root in roots:
        prefix = root.rstrip("/") + "/"
        if path.startswith(prefix):
            return path[len(prefix) :]
    return None


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    report = Path(argv[1])
    if len(argv) > 2:
        workspace = argv[2]
    else:
        workspace = os.environ.get("GITHUB_WORKSPACE") or str(
            Path(__file__).resolve().parent.parent
        )

    tree = ET.parse(report)
    root = tree.getroot()

    # The macOS runner checks out to /Users/runner/work/<repo>/<repo> while the
    # Linux runner uses /home/runner/work/<repo>/<repo>. Accept either shape so
    # the script works no matter which runner invokes it.
    tail = "/".join(Path(workspace).parts[-2:])
    roots = [workspace, f"/Users/runner/work/{tail}", f"/home/runner/work/{tail}"]

    kept = 0
    dropped = 0
    for element in list(root.findall("file")):
        path = element.get("path", "")
        relative = repo_relative(path, roots)
        if relative is None:
            root.remove(element)
            dropped += 1
        else:
            element.set("path", relative)
            kept += 1

    if kept == 0:
        print(
            f"error: no coverage entries resolved under {workspace}; "
            "refusing to write an empty report",
            file=sys.stderr,
        )
        return 1

    tree.write(report, encoding="utf-8", xml_declaration=True)
    print(f"normalized {report}: kept {kept} files, dropped {dropped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
