#!/usr/bin/env python3
"""Keep .swiftlint.baseline from growing.

Usage:
    scripts/swiftlint-baseline.py check OLD NEW
    scripts/swiftlint-baseline.py update CURRENT FRESH

SwiftLint matches a baseline entry by its message, which holds the measured
size ("currently spans 77 lines"), so shrinking a grandfathered file or
function fails lint just like growing it. `update` replaces CURRENT with FRESH
(a `swiftlint lint --write-baseline` run) when FRESH only removes entries or
lowers their sizes, and keeps the old entry wherever nothing but its line
number changed. `check` fails when NEW adds an entry or raises a size
compared with OLD, which catches a baseline raised by hand.
"""

import json
import re
import sys
from collections import Counter, defaultdict

RULES = {
    "cyclomatic_complexity",
    "file_length",
    "function_body_length",
    "nesting",
    "type_body_length",
}


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def size(entry):
    numbers = re.findall(r"\d+", entry["violation"]["reason"])
    return int(numbers[-1]) if numbers else 0


def grouped(entries):
    # Line numbers move with every edit, so an entry is its file, rule and source line.
    groups = defaultdict(list)
    for entry in entries:
        violation = entry["violation"]
        key = (violation["location"]["file"], violation["ruleIdentifier"], entry.get("text", ""))
        groups[key].append(size(entry))
    return {key: sorted(sizes, reverse=True) for key, sizes in groups.items()}


def keep_unchanged(old, new):
    # A fresh run renumbers entries of files nobody touched; keep the old entry when only its line moved.
    # Exact matches are claimed first so two fresh entries never take the same old line.
    unclaimed = Counter(line_key(entry) for entry in old)
    exact = []
    for entry in new:
        exact.append(unclaimed[line_key(entry)] > 0)
        unclaimed[line_key(entry)] -= exact[-1]
    pool = defaultdict(list)
    for entry in old:
        if unclaimed[line_key(entry)] > 0:
            unclaimed[line_key(entry)] -= 1
            pool[entry_key(entry)].append(entry)
    return [
        pool[entry_key(entry)].pop(0) if not is_exact and pool[entry_key(entry)] else entry
        for entry, is_exact in zip(new, exact)
    ]


def entry_key(entry):
    violation = entry["violation"]
    return (violation["location"]["file"], violation["ruleIdentifier"], entry.get("text", ""), violation["reason"])


def line_key(entry):
    return (*entry_key(entry), entry["violation"]["location"].get("line"))


def growth(old, new):
    problems = []
    for entry in new:
        rule = entry["violation"]["ruleIdentifier"]
        if rule not in RULES:
            problems.append(f"{entry['violation']['location']['file']}: {rule} can't be baselined")
    old_groups = grouped(old)
    for key, sizes in grouped(new).items():
        file, rule, text = key
        before = old_groups.get(key, [])
        label = f"{file}: {rule} at `{text.strip()}`"
        if len(sizes) > len(before):
            problems.append(f"{label} is new")
            continue
        for now, was in zip(sizes, before):
            if now > was:
                problems.append(f"{label} grew from {was} to {now}")
    return problems


def main(argv):
    if len(argv) != 4 or argv[1] not in {"check", "update"}:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    command, old_path, new_path = argv[1:]
    old, new = load(old_path), load(new_path)
    problems = growth(old, new)
    if problems:
        print("error: the SwiftLint baseline can only shrink:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    if command == "update":
        new = keep_unchanged(old, new)
        # A stable order keeps the next update's diff to the entries that changed.
        new.sort(key=lambda entry: (
            entry["violation"]["location"]["file"],
            entry["violation"]["location"].get("line") or 0,
            entry["violation"]["ruleIdentifier"],
        ))
        with open(old_path, "w", encoding="utf-8") as handle:
            json.dump(new, handle, indent=1, sort_keys=True, ensure_ascii=False)
            handle.write("\n")
        print(f"Baseline updated: {len(old)} entries before, {len(new)} now.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
