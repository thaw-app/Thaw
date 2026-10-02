import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from xml.dom import minidom

ACTION_PATH = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ACTION_PATH))
from prepare_appcasts import SPARKLE_NS, prepare_appcasts


def feed(*versions):
    items = "".join(
        f"""<item>
  <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
  <description><![CDATA[<p>Notes & details</p>]]></description>
  <enclosure url="https://example.org/{version}.zip" sparkle:edSignature="signature-{version}" length="123" type="application/octet-stream"/>
</item>"""
        for version in versions
    )
    return f'<rss xmlns:sparkle="{SPARKLE_NS}" version="2.0"><channel><title>Thaw</title>{items}</channel></rss>'.encode()


def versions(xml):
    with minidom.parseString(xml) as document:
        return [node.firstChild.data for node in document.getElementsByTagNameNS(SPARKLE_NS, "shortVersionString")]


class PrepareAppcastsTests(unittest.TestCase):
    def test_mixed_feed_keeps_all_canonical_entries_and_only_legacy_versions_in_mirror(self):
        all_versions = ["3.0.0-alpha.7", "3.0.0-beta.1", "3.0.0", "4.0.0", "2.1.0-beta.6", "2.0.1", "1.2.0"]
        canonical, legacy = prepare_appcasts(feed(*all_versions), "2.1.0-beta.6")
        self.assertEqual(versions(canonical), all_versions)
        self.assertEqual(versions(legacy), ["2.1.0-beta.6", "2.0.1", "1.2.0"])
        for xml in (canonical, legacy):
            self.assertIn(b"<![CDATA[<p>Notes & details</p>]]>", xml)
            with minidom.parseString(xml) as document:
                for item in document.getElementsByTagName("item"):
                    version = item.getElementsByTagNameNS(SPARKLE_NS, "shortVersionString")[0].firstChild.data
                    enclosure = item.getElementsByTagName("enclosure")[0]
                    self.assertEqual(enclosure.getAttributeNS(SPARKLE_NS, "edSignature"), f"signature-{version}")
                    self.assertEqual(enclosure.getAttribute("url"), f"https://example.org/{version}.zip")
                    self.assertEqual(enclosure.getAttribute("length"), "123")
                    caps = item.getElementsByTagNameNS(SPARKLE_NS, "maximumSystemVersion")
                    self.assertEqual([cap.firstChild.data for cap in caps], ["26.99"] if version.startswith("2.") else [])

    def test_existing_cap_is_preserved_and_preparation_is_idempotent(self):
        xml = feed("2.0.1").replace(b"</item>", b"<sparkle:maximumSystemVersion>26.5</sparkle:maximumSystemVersion></item>")
        canonical, legacy = prepare_appcasts(xml, "2.0.1")
        self.assertEqual(prepare_appcasts(canonical, "2.0.1"), (canonical, legacy))
        self.assertIn(b">26.5<", canonical)
        self.assertNotIn(b">26.99<", canonical)

    def test_new_cap_is_idempotent(self):
        canonical, legacy = prepare_appcasts(feed("2.0.1", "1.2.0"), "2.0.1")
        self.assertEqual(prepare_appcasts(canonical, "2.0.1"), (canonical, legacy))
        self.assertEqual(versions(legacy), ["2.0.1", "1.2.0"])

    def test_three_x_release_still_caps_two_x_but_has_no_legacy_feed(self):
        canonical, legacy = prepare_appcasts(feed("3.0.0-beta.1", "2.0.1"), "3.0.0-beta.1")
        self.assertIsNone(legacy)
        self.assertIn(b">26.99<", canonical)
        self.assertEqual(versions(canonical), ["3.0.0-beta.1", "2.0.1"])

    def test_alternate_namespace_prefix(self):
        xml = feed("2.0.1").replace(b"sparkle:", b"s:").replace(b"xmlns:sparkle=", b"xmlns:s=")
        canonical, _ = prepare_appcasts(xml, "2.0.1")
        self.assertIn(b"<s:maximumSystemVersion>26.99</s:maximumSystemVersion>", canonical)
        minidom.parseString(canonical).unlink()

    def test_missing_version_or_minimum_fails(self):
        for field in ("shortVersionString", "minimumSystemVersion"):
            with self.subTest(field=field):
                xml = feed("2.0.1")
                with minidom.parseString(xml) as document:
                    node = document.getElementsByTagNameNS(SPARKLE_NS, field)[0]
                    node.parentNode.removeChild(node)
                    xml = document.toxml(encoding="utf-8")
                with self.assertRaises(ValueError):
                    prepare_appcasts(xml, "2.0.1")

    def test_empty_feed(self):
        canonical, legacy = prepare_appcasts(feed(), "2.0.1")
        self.assertEqual(versions(canonical), [])
        self.assertEqual(versions(legacy), [])

    def test_channel_items_show_their_tag_and_promoted_items_keep_the_bundle_version(self):
        def item(build, short, tag, channel):
            channel = f"<sparkle:channel>{channel}</sparkle:channel>" if channel else ""
            # Like the live feed: delta enclosures nest inside sparkle:deltas.
            return f"""<item>
  <sparkle:version>{build}</sparkle:version>
  <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
  {channel}
  <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
  <enclosure url="https://example.org/download/{tag}/Thaw_{tag}.zip" length="1" type="application/octet-stream"/>
  <sparkle:deltas>
    <enclosure url="https://example.org/download/{tag}/Thaw{build}-60.delta" sparkle:deltaFrom="60" length="1"/>
    <enclosure url="https://example.org/download/{tag}/Thaw{build}-59.delta" sparkle:deltaFrom="59" length="1"/>
  </sparkle:deltas>
</item>"""

        items = "".join([
            item(64, "2.1.1", "2.1.1-rc.1", "beta"),  # built with its final version
            item(63, "2.1.0", "2.1.0-rc.1", None),  # promoted: channel removed
            item(62, "2.1.0-beta.6", "2.1.0-beta.6", "beta"),
            item(56, "2.0.1", "2.0.1", None),
        ])
        xml = f'<rss xmlns:sparkle="{SPARKLE_NS}" version="2.0"><channel>{items}</channel></rss>'.encode()
        canonical, legacy = prepare_appcasts(xml, "2.1.1-rc.1")
        self.assertEqual(versions(canonical), ["2.1.1-rc.1", "2.1.0", "2.1.0-beta.6", "2.0.1"])
        self.assertEqual(versions(legacy), versions(canonical))
        self.assertEqual(prepare_appcasts(canonical, "2.1.1-rc.1"), (canonical, legacy))

    def test_notes_generate_appcast_dropped_come_back_from_the_previous_feed(self):
        def item(build, notes):
            description = f"<description><![CDATA[{notes}]]></description>" if notes is not None else ""
            return f"""<item>
  <sparkle:version>{build}</sparkle:version>
  <sparkle:shortVersionString>2.1.{build}</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
  {description}
  <enclosure url="https://example.org/Thaw_2.1.{build}.zip" length="1" type="application/octet-stream"/>
</item>"""

        def wrap(*items):
            body = "".join(items)
            return f'<rss xmlns:sparkle="{SPARKLE_NS}" version="2.0"><channel>{body}</channel></rss>'.encode()

        previous = wrap(item(2, "<p>Two & more</p>"), item(1, "<p>One</p>"))
        generated = wrap(item(3, "<p>Three</p>"), item(2, None), item(1, ""))
        canonical, _ = prepare_appcasts(generated, "2.1.3", previous)
        with minidom.parseString(canonical) as document:
            notes = {
                item.getElementsByTagNameNS(SPARKLE_NS, "version")[0].firstChild.data:
                    [node.firstChild.data for node in item.getElementsByTagName("description")]
                for item in document.getElementsByTagName("item")
            }
        self.assertEqual(notes, {"3": ["<p>Three</p>"], "2": ["<p>Two & more</p>"], "1": ["<p>One</p>"]})
        self.assertIn(b"<![CDATA[<p>Two & more</p>]]>", canonical)
        self.assertEqual(prepare_appcasts(canonical, "2.1.3", previous)[0], canonical)

    def test_action_entry_point_outputs_paths_without_modifying_source(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source = directory / "source.xml"
            original = feed("3.0.0", "2.0.1")
            source.write_bytes(original)
            output = directory / "outputs"
            for tag in ("2.0.1", "3.0.0"):
                with self.subTest(tag=tag):
                    output.write_text("")
                    result = subprocess.run(
                        [sys.executable, str(ACTION_PATH / "prepare_appcasts.py")],
                        env=dict(os.environ, APPCAST_PATH=str(source), RELEASE_TAG=tag,
                                 RUNNER_TEMP=str(directory), GITHUB_OUTPUT=str(output)),
                        capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
                    self.assertEqual(versions(Path(outputs["appcast-path"]).read_bytes()), ["3.0.0", "2.0.1"])
                    if tag.startswith("2."):
                        self.assertEqual(versions(Path(outputs["legacy-appcast-path"]).read_bytes()), ["2.0.1"])
                    else:
                        self.assertEqual(outputs["legacy-appcast-path"], "")
                        self.assertFalse((directory / "thaw-appcasts/legacy-appcast.xml").exists())
                    self.assertEqual(source.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
