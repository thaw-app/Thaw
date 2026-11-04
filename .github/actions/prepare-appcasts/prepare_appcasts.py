from __future__ import annotations

import os
import re
from pathlib import Path
from xml.dom import Node, minidom

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

# Sparkle splits Macs into 7 groups and opens one per interval from pubDate,
# so 4 hours lets every group in 24 hours after publishing.
PHASED_ROLLOUT_INTERVAL_SECONDS = "14400"


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


def insert_sparkle_element_after(document, anchor, name, value):
    qualified_name = f"{anchor.prefix}:{name}" if anchor.prefix else name
    element = document.createElementNS(SPARKLE_NS, qualified_name)
    element.appendChild(document.createTextNode(value))
    item = anchor.parentNode
    spacing = anchor.nextSibling
    item.insertBefore(element, spacing)
    if spacing and spacing.nodeType == Node.TEXT_NODE and not spacing.data.strip():
        item.insertBefore(spacing.cloneNode(True), element)


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
    xml: bytes, release_tag: str, previous_xml: bytes | None = None, staged: bool = True
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
                insert_sparkle_element_after(document, minimums[0], "maximumSystemVersion", "26.99")

            # Stage everything but alpha, and an unstaged release's own item, which reaches every Mac at once.
            # Older items are past their last group, so the tag changes nothing for them.
            channels = [text(channel) for channel in sparkle_elements(item, "channel")]
            # A channel on the item wins, because Release can override the one a tag implies.
            is_alpha = "alpha" in channels if channels else re.search(r"-(alpha|nightly)(\.|$)", version, re.IGNORECASE)
            # By the enclosure tag first: an item built with its final version shows 2.1.1 for 2.1.1-rc.1.
            unstaged = not staged and release_tag in (tag, text(versions[0]))
            if not is_alpha and not unstaged and not sparkle_elements(item, "phasedRolloutInterval"):
                insert_sparkle_element_after(
                    document, versions[0], "phasedRolloutInterval", PHASED_ROLLOUT_INTERVAL_SECONDS
                )

            if not version.startswith(("1.", "2.")):
                legacy_exclusions.append(item)

        canonical = document.toxml(encoding="utf-8")
        if not release_tag.startswith("2."):
            return canonical, None

        for item in legacy_exclusions:
            item.parentNode.removeChild(item)
            item.unlink()
        return canonical, document.toxml(encoding="utf-8")


def main(staged: bool = True):
    previous_path = os.environ.get("PREVIOUS_APPCAST_PATH", "")
    previous = Path(previous_path).read_bytes() if previous_path and Path(previous_path).is_file() else None
    canonical, legacy = prepare_appcasts(
        Path(os.environ["APPCAST_PATH"]).read_bytes(), os.environ["RELEASE_TAG"], previous, staged
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
