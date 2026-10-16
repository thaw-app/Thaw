from __future__ import annotations

import os
import re
from pathlib import Path
from xml.dom import Node, minidom

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def sparkle_elements(item, name):
    return [
        child for child in item.childNodes
        if child.nodeType == Node.ELEMENT_NODE
        and child.namespaceURI == SPARKLE_NS and child.localName == name
    ]


# The release tag in an enclosure file name: Thaw_2.1.0-rc.1.zip, or a bare 2.1.0-rc.1.zip.
ENCLOSURE_TAG = re.compile(r"(?:^|_)(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\.zip$")


def text(element):
    return "".join(
        node.data for node in element.childNodes
        if node.nodeType in (Node.TEXT_NODE, Node.CDATA_SECTION_NODE)
    ).strip()


def build_number(item):
    builds = sparkle_elements(item, "version")
    return text(builds[0]) if len(builds) == 1 else None


def has_description(item):
    return any(text(node) for node in item.getElementsByTagName("description"))


def update_enclosures(item):
    # Direct children only: delta enclosures nest inside sparkle:deltas.
    return [
        child for child in item.childNodes
        if child.nodeType == Node.ELEMENT_NODE and child.namespaceURI is None
        and child.localName == "enclosure"
    ]


def enclosure_tag(item):
    enclosures = update_enclosures(item)
    if len(enclosures) != 1:
        return None
    match = ENCLOSURE_TAG.search(enclosures[0].getAttribute("url").rsplit("/", 1)[-1])
    return match.group(1) if match else None


def previous_descriptions(xml: bytes | None):
    if not xml:
        return {}
    with minidom.parseString(xml) as document:
        return {
            build: item.getElementsByTagName("description")[0].cloneNode(True)
            for item in document.getElementsByTagName("item")
            if (build := build_number(item)) and has_description(item)
        }


def prepare_appcasts(
    xml: bytes, release_tag: str, previous_xml: bytes | None = None
) -> tuple[bytes, bytes | None]:
    descriptions = previous_descriptions(previous_xml)
    # DOM serialization preserves CDATA, namespace prefixes, and enclosure signatures.
    with minidom.parseString(xml) as document:
        legacy_exclusions = []
        for item in document.getElementsByTagName("item"):
            # generate_appcast drops the notes of every prior archive it re-reads
            # for deltas, so carry them over from the feed it started from.
            build = build_number(item)
            if build in descriptions and not has_description(item):
                for empty in item.getElementsByTagName("description"):
                    item.removeChild(empty)
                restored = document.importNode(descriptions[build], True)
                enclosures = update_enclosures(item)
                item.insertBefore(restored, enclosures[0] if enclosures else None)

            versions = sparkle_elements(item, "shortVersionString")
            if len(versions) != 1:
                raise ValueError("Appcast item must have one sparkle:shortVersionString")

            # Prereleases are built with their final version so they can be
            # promoted unchanged. On a channel, show the tag (2.1.0-rc.1);
            # once promoted, the channel is gone and the bundle's 2.1.0 stays.
            # generate_appcast resets this from the bundle, so reapply every run.
            tag = enclosure_tag(item)
            if sparkle_elements(item, "channel") and tag and "-" in tag and text(versions[0]) != tag:
                for node in list(versions[0].childNodes):
                    versions[0].removeChild(node)
                versions[0].appendChild(document.createTextNode(tag))

            version = text(versions[0])
            if not version:
                raise ValueError("Appcast item has an empty sparkle:shortVersionString")

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
    previous_path = os.environ.get("PREVIOUS_APPCAST_PATH", "")
    previous = Path(previous_path).read_bytes() if previous_path and Path(previous_path).is_file() else None
    canonical, legacy = prepare_appcasts(
        Path(os.environ["APPCAST_PATH"]).read_bytes(), os.environ["RELEASE_TAG"], previous
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
