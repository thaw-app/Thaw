#!/usr/bin/env python3
"""Turn Swift package test coverage into SonarQube's generic coverage XML.

Usage:
    scripts/package-coverage.py convert <codecov.json> <out.xml> [repo-root]
    scripts/package-coverage.py merge <out.xml> <report.xml> [<report.xml> ...]

`swift test --enable-code-coverage` writes an llvm-cov JSON export; the path is
printed by `swift test --show-codecov-path`. `convert` keeps the files under a
package's Sources folder, rewrites their paths relative to the repository and
writes one line entry per instrumented line, counted the way `llvm-cov show`
counts lines.

The app's xcresult report (see normalize-coverage.py) and each package's report
are separate files, and the Sonar scan takes one file per report property.
`merge` combines them. A file that appears in more than one report, such as a
package the app tests also run, is covered on a line if any report covers it.
"""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Segment layout in the llvm-cov export:
# [line, column, count, hasCount, isRegionEntry, isGapRegion]
LINE, _COLUMN, COUNT, HAS_COUNT, IS_ENTRY, IS_GAP = range(6)


def line_counts(segments: list[list]) -> dict[int, int]:
    """Return the execution count of each instrumented line.

    This follows llvm-cov's own line statistics. The segment that is still open
    when a line starts (the last one on an earlier line) is the line's base: the
    line is instrumented if that segment has a count, or if a counted region
    starts on it, and its count is the highest of the base and those regions.
    Gap regions never start a region. A line that begins a skipped region is not
    instrumented, unless a counted region also starts on it: llvm maps any line
    where a counted region entry starts.
    """
    counts: dict[int, int] = {}
    wrapped: list | None = None  # last segment before the current line
    index = 0
    previous_line = 0
    while index < len(segments):
        line = segments[index][LINE]
        # Lines between two segments belong to the region that is still open.
        if wrapped is not None and wrapped[HAS_COUNT]:
            for between in range(previous_line + 1, line):
                counts[between] = wrapped[COUNT]
        group = []
        while index < len(segments) and segments[index][LINE] == line:
            group.append(segments[index])
            index += 1
        starting = [
            segment[COUNT]
            for segment in group
            if segment[HAS_COUNT] and segment[IS_ENTRY] and not segment[IS_GAP]
        ]
        skipped = not group[0][HAS_COUNT] and group[0][IS_ENTRY]
        wrapped_counted = wrapped is not None and wrapped[HAS_COUNT]
        counted_entry = any(segment[HAS_COUNT] and segment[IS_ENTRY] for segment in group)
        if (not skipped and (wrapped_counted or starting)) or counted_entry:
            base = wrapped[COUNT] if wrapped is not None else 0
            counts[line] = max([base, *starting])
        wrapped = group[-1]
        previous_line = line
    return counts


def relative_to(path: str, root: Path) -> str | None:
    """Return `path` relative to `root`, or None when it is not a package source."""
    try:
        relative = Path(path).resolve().relative_to(root)
    except ValueError:
        return None
    parts = relative.parts
    # Only code a package ships: not its tests, build output or generated entry point.
    if "Sources" not in parts or ".build" in parts or "Tests" in parts:
        return None
    return relative.as_posix()


def convert(codecov: Path, output: Path, root: Path) -> int:
    export = json.loads(codecov.read_text(encoding="utf-8"))
    report = ET.Element("coverage", version="1")
    files = 0
    for data in export["data"]:
        for entry in data["files"]:
            relative = relative_to(entry["filename"], root)
            if relative is None:
                continue
            element = ET.SubElement(report, "file", path=relative)
            for number, count in sorted(line_counts(entry["segments"]).items()):
                ET.SubElement(
                    element,
                    "lineToCover",
                    lineNumber=str(number),
                    covered="true" if count > 0 else "false",
                )
            files += 1
    if files == 0:
        print(f"error: no package sources found in {codecov}", file=sys.stderr)
        return 1
    ET.indent(report)
    ET.ElementTree(report).write(output, encoding="utf-8", xml_declaration=True)
    print(f"wrote {output}: {files} files")
    return 0


def merge(output: Path, reports: list[Path]) -> int:
    merged: dict[str, dict[str, bool]] = {}
    for report in reports:
        for element in ET.parse(report).getroot().findall("file"):
            lines = merged.setdefault(element.get("path", ""), {})
            for line in element.findall("lineToCover"):
                number = line.get("lineNumber", "")
                covered = line.get("covered") == "true"
                lines[number] = lines.get(number, False) or covered
    root = ET.Element("coverage", version="1")
    for path in sorted(merged):
        element = ET.SubElement(root, "file", path=path)
        for number in sorted(merged[path], key=int):
            ET.SubElement(
                element,
                "lineToCover",
                lineNumber=number,
                covered="true" if merged[path][number] else "false",
            )
    ET.indent(root)
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)
    print(f"merged {len(reports)} reports into {output}: {len(merged)} files")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 4 and argv[1] == "convert":
        root = Path(argv[4]).resolve() if len(argv) > 4 else Path.cwd().resolve()
        return convert(Path(argv[2]), Path(argv[3]), root)
    if len(argv) >= 4 and argv[1] == "merge":
        return merge(Path(argv[2]), [Path(path) for path in argv[3:]])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
