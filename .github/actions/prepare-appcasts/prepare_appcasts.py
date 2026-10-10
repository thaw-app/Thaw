from __future__ import annotations

import os
from pathlib import Path
from xml.dom import Node, minidom

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def sparkle_elements(item, name):
    return [
        child for child in item.childNodes
        if child.nodeType == Node.ELEMENT_NODE
        and child.namespaceURI == SPARKLE_NS and child.localName == name
    ]


def prepare_appcasts(xml: bytes, release_tag: str) -> tuple[bytes, bytes | None]:
    # DOM serialization preserves CDATA, namespace prefixes, and enclosure signatures.
    with minidom.parseString(xml) as document:
        legacy_exclusions = []
        for item in document.getElementsByTagName("item"):
            versions = sparkle_elements(item, "shortVersionString")
            if len(versions) != 1:
                raise ValueError("Appcast item must have one sparkle:shortVersionString")
            version = "".join(
                node.data for node in versions[0].childNodes
                if node.nodeType in (Node.TEXT_NODE, Node.CDATA_SECTION_NODE)
            ).strip()
            if not version:
                raise ValueError("Appcast item has an empty sparkle:shortVersionString")

            # Alpha 7 accepts only alpha and untagged items. Keep beta 1 reachable
            # even if generate_appcast restores its original beta channel.
            if version == "3.0.0-beta.1":
                minimums = sparkle_elements(item, "minimumSystemVersion")
                if len(minimums) != 1 or minimums[0].firstChild is None or minimums[0].firstChild.data.strip() != "27.0":
                    raise ValueError("3.0.0-beta.1 recovery bridge requires macOS 27.0")
                for channel in sparkle_elements(item, "channel"):
                    item.removeChild(channel)
                    channel.unlink()

            # generate_appcast can rewrite prior entries, so reapply missing caps on every run.
            if version.startswith("2.") and not sparkle_elements(item, "maximumSystemVersion"):
                minimums = sparkle_elements(item, "minimumSystemVersion")
                if len(minimums) != 1:
                    raise ValueError(f"{version} must have one minimumSystemVersion to anchor the cap on")
                minimum = minimums[0]
                name = f"{minimum.prefix}:maximumSystemVersion" if minimum.prefix else "maximumSystemVersion"
                maximum = document.createElementNS(SPARKLE_NS, name)
                maximum.appendChild(document.createTextNode("26.99"))
                spacing = minimum.nextSibling
                item.insertBefore(maximum, spacing)
                if spacing and spacing.nodeType == Node.TEXT_NODE and not spacing.data.strip():
                    item.insertBefore(spacing.cloneNode(True), maximum)

            if not version.startswith(("1.", "2.")):
                legacy_exclusions.append(item)

        canonical = document.toxml(encoding="utf-8")
        if not release_tag.startswith("2."):
            return canonical, None

        for item in legacy_exclusions:
            item.parentNode.removeChild(item)
            item.unlink()
        return canonical, document.toxml(encoding="utf-8")


def main():
    canonical, legacy = prepare_appcasts(
        Path(os.environ["APPCAST_PATH"]).read_bytes(), os.environ["RELEASE_TAG"]
    )
    directory = Path(os.environ["RUNNER_TEMP"]) / "thaw-appcasts"
    directory.mkdir(parents=True, exist_ok=True)
    canonical_path = directory / "appcast.xml"
    canonical_path.write_bytes(canonical)
    legacy_path = directory / "legacy-appcast.xml"
    if legacy is not None:
        legacy_path.write_bytes(legacy)
    else:
        legacy_path.unlink(missing_ok=True)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"appcast-path={canonical_path}\n")
        output.write(f"legacy-appcast-path={legacy_path if legacy is not None else ''}\n")


if __name__ == "__main__":
    main()
