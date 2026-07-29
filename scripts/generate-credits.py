#!/usr/bin/env python3
"""Generate CREDITS.md from a Crowdin top-members CSV export.

Usage:
    scripts/generate-credits.py path/to/Thaw.top_members.report.csv

Export the CSV from Crowdin: Project -> Reports -> Top Members -> Export.

Members with zero translated words are skipped. The overrides below carry
corrections that the export cannot express; keep them up to date, because a
fresh export will otherwise silently drop them.
"""

import collections
import csv
import io
import sys
from pathlib import Path

# --- Overrides -------------------------------------------------------------

# Restrict a member to specific source languages (Crowdin names).
ONLY = {
    "René (diazdesandi)": {"Spanish"},
}

# Replace a member's display name.
RENAME = {
    "REMOVED_USER": "Anonymous (account deleted)",
}

# Collapse pathological display names to their handle.
def normalize_name(name: str) -> str:
    if name.count("᥮") > 5:
        return "wlo2"
    return RENAME.get(name, name)

# People who contribute but do not appear in the members export, e.g. project
# owners and managers, whose activity Crowdin records separately.
EXTRA = {
    "Deutsch": ["Toni Forster (stonerl)"],
}

# --- Language mapping ------------------------------------------------------

LANGUAGES = {
    "Indonesian": ("🇮🇩", "Bahasa Indonesia"),
    "Czech": ("🇨🇿", "Čeština"),
    "German": ("🇩🇪 🇦🇹", "Deutsch"),
    "Spanish": ("🇪🇸 🇲🇽", "Español"),
    "French": ("🇫🇷", "Français"),
    "Italian": ("🇮🇹", "Italiano"),
    "Hungarian": ("🇭🇺", "Magyar"),
    "Dutch": ("🇳🇱 🇧🇪", "Nederlands"),
    "Polish": ("🇵🇱", "Polski"),
    "Brazilian": ("🇧🇷", "Português (Brasil)"),
    "Portuguese": ("🇧🇷", "Português (Brasil)"),
    "Turkish": ("🇹🇷", "Türkçe"),
    "Russian": ("🇷🇺", "Русский"),
    "Ukrainian": ("🇺🇦", "Українська"),
    "Thai": ("🇹🇭", "ภาษาไทย"),
    "Vietnamese": ("🇻🇳", "Tiếng Việt"),
    "Japanese": ("🇯🇵", "日本語"),
    "Korean": ("🇰🇷", "한국어"),
    "Chinese Simplified": ("🇨🇳", "简体中文"),
    "Chinese Traditional": ("🇹🇼", "正體中文"),
}

# Display order, matching the README's Languages table.
ORDER = [
    "Bahasa Indonesia", "Čeština", "Deutsch", "Español", "Français",
    "Italiano", "Magyar", "Nederlands", "Polski", "Português (Brasil)",
    "Türkçe", "Русский", "Українська", "ภาษาไทย", "Tiếng Việt",
    "日本語", "한국어", "简体中文", "正體中文",
]

FLAGS = {native: flag for flag, native in LANGUAGES.values()}


def words(row, key):
    try:
        return int((row.get(key) or "0").replace(",", "") or 0)
    except ValueError:
        return 0


def collect(csv_path):
    rows = list(csv.DictReader(open(csv_path, encoding="utf-8-sig")))
    by_language = collections.defaultdict(set)

    for row in rows:
        if words(row, "Translated (Words)") <= 0:
            continue
        raw = row["Name"].strip()
        langs = [
            part.strip()
            for chunk in row["Languages"].split(";")
            for part in chunk.split(",")
            if part.strip()
        ]
        if raw in ONLY:
            langs = [lang for lang in langs if lang in ONLY[raw]]
        for lang in langs:
            if lang in LANGUAGES:
                by_language[LANGUAGES[lang][1]].add(normalize_name(raw))

    for native, people in EXTRA.items():
        by_language[native].update(people)

    return by_language


def render(by_language):
    out = io.StringIO()
    out.write("# Credits\n\n")
    out.write("Thaw is translated by volunteers on "
              "[Crowdin](https://crowdin.com/project/thaw).\n")
    out.write("Everyone below has contributed translated strings to the app.\n\n")
    out.write("Want to join them, or spotted a translation that could be better?\n")
    out.write("[Translate Thaw on Crowdin](https://crowdin.com/project/thaw) — "
              "you can request\nnew languages there too.\n\n")
    out.write("## Translators\n\n")
    out.write("Listed alphabetically within each language, not by volume.\n\n")

    for native in ORDER:
        people = sorted(by_language.get(native, ()), key=str.casefold)
        if not people:
            continue
        out.write(f"### {FLAGS[native]} {native}\n\n")
        for person in people:
            out.write(f"- {person}\n")
        out.write("\n")

    out.write("---\n\n")
    out.write("Names are Crowdin display names, taken from the project's "
              "top-members\nreport. To have yours changed or removed, open an "
              "issue or say so on\n[Discord](https://discord.gg/5cnKkKbMFd).\n")
    return out.getvalue()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    by_language = collect(sys.argv[1])
    target = Path(__file__).resolve().parent.parent / "CREDITS.md"
    target.write_text(render(by_language), encoding="utf-8")
    people = {person for group in by_language.values() for person in group}
    print(f"wrote {target.name}: {len(people)} people, "
          f"{sum(1 for l in ORDER if by_language.get(l))} languages")


if __name__ == "__main__":
    main()
