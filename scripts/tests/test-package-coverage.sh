#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
SCRIPT="$ROOT/scripts/package-coverage.py"
REPO="$TEMP_DIR/repo"

# Prints "path line=T|F ..." for every file in a generic coverage report.
summary() {
    python3 - "$1" <<'PY'
import sys
import xml.etree.ElementTree as ET

for file in ET.parse(sys.argv[1]).getroot():
    lines = " ".join(
        f"{line.get('lineNumber')}={'T' if line.get('covered') == 'true' else 'F'}"
        for line in file
    )
    print(file.get("path"), lines)
PY
}

# Segments are [line, column, count, hasCount, isRegionEntry, isGapRegion].
# Line 1 opens a region run 3 times and a nested region at line 3 never runs, but
# the line still takes its base count. Line 6 is outside every region. Line 7 is
# a region that never runs. Line 11 starts a gap region, which never counts, and
# line 12 sits inside that gap. Line 14 begins with a region that is skipped but
# a counted region also starts on it, so llvm still maps the line.
cat > "$TEMP_DIR/export.json" <<JSON
{"data":[{"files":[
  {"filename":"$REPO/packages/Foo/Sources/Foo/A.swift","segments":[
    [1,1,3,true,true,false],[3,5,0,true,true,false],[3,20,3,true,false,false],
    [5,1,0,false,false,false],[7,1,0,true,true,false],[8,1,0,false,false,false],
    [10,1,2,true,true,false],[11,1,0,true,true,true],[13,1,0,false,false,false],
    [14,1,0,false,true,false],[14,10,5,true,true,false],[15,1,0,false,false,false]]},
  {"filename":"$REPO/packages/Foo/Tests/FooTests/ATests.swift","segments":[[1,1,1,true,true,false],[2,1,0,false,false,false]]},
  {"filename":"$REPO/packages/Foo/.build/checkouts/Dep/Sources/Dep/D.swift","segments":[[1,1,1,true,true,false],[2,1,0,false,false,false]]},
  {"filename":"/elsewhere/Sources/E.swift","segments":[[1,1,1,true,true,false],[2,1,0,false,false,false]]}
]}]}
JSON
mkdir -p "$REPO"

python3 "$SCRIPT" convert "$TEMP_DIR/export.json" "$TEMP_DIR/a.xml" "$REPO" > /dev/null
expected="packages/Foo/Sources/Foo/A.swift 1=T 2=T 3=T 4=T 5=T 7=F 8=F 10=T 11=T 12=F 13=F 14=T 15=T"
actual=$(summary "$TEMP_DIR/a.xml")
if [[ "$actual" != "$expected" ]]; then
    printf 'convert: expected\n%s\ngot\n%s\n' "$expected" "$actual" >&2
    exit 1
fi

# Merging keeps a line covered when any report covers it and keeps every file.
cat > "$TEMP_DIR/b.xml" <<'XML'
<coverage version="1">
  <file path="packages/Foo/Sources/Foo/A.swift">
    <lineToCover lineNumber="7" covered="true"/>
    <lineToCover lineNumber="20" covered="false"/>
  </file>
  <file path="Thaw/B.swift">
    <lineToCover lineNumber="1" covered="false"/>
  </file>
</coverage>
XML
python3 "$SCRIPT" merge "$TEMP_DIR/merged.xml" "$TEMP_DIR/a.xml" "$TEMP_DIR/b.xml" > /dev/null
expected="Thaw/B.swift 1=F
packages/Foo/Sources/Foo/A.swift 1=T 2=T 3=T 4=T 5=T 7=T 8=F 10=T 11=T 12=F 13=F 14=T 15=T 20=F"
actual=$(summary "$TEMP_DIR/merged.xml")
if [[ "$actual" != "$expected" ]]; then
    printf 'merge: expected\n%s\ngot\n%s\n' "$expected" "$actual" >&2
    exit 1
fi

# An export with no package sources fails instead of writing an empty report.
printf '{"data":[{"files":[]}]}' > "$TEMP_DIR/empty.json"
status=0
python3 "$SCRIPT" convert "$TEMP_DIR/empty.json" "$TEMP_DIR/empty.xml" "$REPO" > /dev/null 2>&1 || status=$?
if [[ "$status" != 1 ]]; then
    printf 'convert of an empty export: expected exit 1, got %s\n' "$status" >&2
    exit 1
fi
