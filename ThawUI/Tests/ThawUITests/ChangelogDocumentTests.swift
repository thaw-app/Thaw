//
//  ChangelogDocumentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawUI

/// Pins ChangelogDocument.parse(_:), the small Keep-a-Changelog parser behind the What's New sheet:
/// its shape (releases, sections, themes, bullets) and how it degrades on input it doesn't recognize.
@MainActor
@Suite("ChangelogDocument parsing")
struct ChangelogDocumentTests {
    /// A bullet's characters, so assertions ignore inline styling runs.
    private func plain(_ text: AttributedString) -> String {
        String(text.characters)
    }

    /// The plain text of a block, so a prose block and a callout assert the same way.
    private func plain(_ block: ChangelogDocument.Block) -> String {
        switch block {
        case let .text(text):
            plain(text)
        case let .callout(callout):
            plain(callout)
        }
    }

    private func plain(_ callout: ChangelogDocument.Callout) -> String {
        callout.parts.map { part in
            switch part {
            case let .paragraph(text), let .bullet(text): plain(text)
            }
        }
        .joined(separator: "\n")
    }

    // MARK: - Document shape

    private static let fullDocument = """
    # Changelog

    All notable changes to this project are documented in this file.

    ## [Unreleased]

    ## [2.1.0] - 2026-02-01

    - A release intro bullet before any section.

    ### Added

    #### Menu bar

    - First bullet.
    - Second bullet.

    #### Panels

    - Panel bullet.

    ### Fixed

    - Direct bullet one.
    - Direct bullet two.

    ## [2.0.0] - 2026-01-01

    ### Changed

    - Older bullet.
    """

    @Test("releases split on '## [version]' headers, in file order")
    func releasesSplitOnVersionHeaders() {
        let document = ChangelogDocument.parse(Self.fullDocument)

        #expect(document.releases.count == 3)
        #expect(document.releases.map(\.version) == ["Unreleased", "2.1.0", "2.0.0"])
    }

    @Test("a release date is the calendar day it says, in the local zone")
    func releaseDateIsTheLocalCalendarDay() {
        let document = ChangelogDocument.parse("## [3.0.0-alpha.2] - 2026-09-10\n\n- one\n")
        let date = document.releases.first?.date
        #expect(date != nil)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date ?? .distantPast)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 10)
        #expect(parts.hour == 0)
    }

    @Test("the version is the bracketed text only, not the date suffix")
    func versionStopsAtClosingBracket() {
        let document = ChangelogDocument.parse(Self.fullDocument)

        #expect(document.releases[1].version == "2.1.0")
        #expect(document.releases[2].version == "2.0.0")
    }

    @Test("'###' headers open sections and '####' headers open themes inside them")
    func sectionsAndThemes() {
        let document = ChangelogDocument.parse(Self.fullDocument)
        let release = document.releases[1]

        #expect(release.sections.map(\.title) == ["Added", "Fixed"])

        let added = release.sections[0]
        #expect(added.themes.map(\.title) == ["Menu bar", "Panels"])
        #expect(added.themes[0].bullets.map(plain) == ["First bullet.", "Second bullet."])
        #expect(added.themes[1].bullets.map(plain) == ["Panel bullet."])
    }

    @Test("a section with direct bullets gets a single unnamed theme")
    func directBulletsBecomeUnnamedTheme() {
        let document = ChangelogDocument.parse(Self.fullDocument)
        let fixed = document.releases[1].sections[1]

        #expect(fixed.themes.count == 1)
        #expect(fixed.themes[0].title == nil)
        #expect(fixed.themes[0].bullets.map(plain) == ["Direct bullet one.", "Direct bullet two."])
    }

    @Test("bullets before a release's first section land in its intro")
    func bulletsBeforeFirstSectionAreIntro() {
        let document = ChangelogDocument.parse(Self.fullDocument)
        let release = document.releases[1]

        #expect(release.intro.map(plain) == ["A release intro bullet before any section."])
    }

    @Test("a GitHub alert parses into a callout with its kind and body")
    func alertParsesIntoCallout() {
        let document = ChangelogDocument.parse("""
        ## [3.0.0]

        > [!WARNING]
        > **Known limitations**
        > Some items may be missing.
        """)
        guard case let .callout(callout)? = document.releases.first?.intro.first else {
            Issue.record("expected a callout in the intro")
            return
        }
        #expect(callout.kind == .warning)
        #expect(plain(callout).contains("Known limitations"))
        #expect(plain(callout).contains("Some items may be missing."))
    }

    @Test("the bold facts line under a heading leaves the intro")
    func factsLineLeavesIntro() {
        let document = ChangelogDocument.parse("""
        ## [3.0.0] - 2026-09-27

        **macOS 27 only · Build 109 · First beta**

        **This line is bold but has no facts.**
        """)
        let release = document.releases.first
        #expect(release?.facts == "macOS 27 only · Build 109 · First beta")
        #expect(release?.intro.map(plain) == ["This line is bold but has no facts."])
    }

    @Test("a list inside an alert keeps its bullets and lead-in lines")
    func alertKeepsItsList() {
        let document = ChangelogDocument.parse("""
        ## [3.0.0]

        > [!TIP]
        > **The short version**
        >
        > **What's new**
        > - First thing.
        > - Second thing.
        >
        > **What's fixed**
        > - Third thing.
        """)
        guard case let .callout(callout)? = document.releases.first?.intro.first else {
            Issue.record("expected a callout in the intro")
            return
        }
        let shape = callout.parts.map { part -> String in
            switch part {
            case let .paragraph(text): "p:" + plain(text)
            case let .bullet(text): "b:" + plain(text)
            }
        }
        #expect(shape == [
            "p:The short version",
            "p:What's new",
            "b:First thing.",
            "b:Second thing.",
            "p:What's fixed",
            "b:Third thing.",
        ])
    }

    @Test("a plain blockquote is still prose")
    func plainBlockquoteStaysProse() {
        let document = ChangelogDocument.parse("""
        ## [3.0.0]

        > Not an alert.
        """)
        guard case let .text(text)? = document.releases.first?.intro.first else {
            Issue.record("expected prose in the intro")
            return
        }
        #expect(plain(text).contains("Not an alert."))
    }

    @Test("an alert after a section lands in that section's theme")
    func alertInSectionLandsInTheme() {
        let document = ChangelogDocument.parse("""
        ## [3.0.0]

        ### Notes

        - A bullet.

        > [!CAUTION]
        > Careful here.
        """)
        let theme = document.releases.first?.sections.first?.themes.first
        #expect(theme?.bullets.count == 2)
        guard case let .callout(callout)? = theme?.bullets.last else {
            Issue.record("expected a callout as the second block")
            return
        }
        #expect(callout.kind == .caution)
    }

    @Test("file preamble and bare prose outside bullets are dropped")
    func preambleProseIsDropped() {
        let document = ChangelogDocument.parse(Self.fullDocument)

        // The '# Changelog' heading and the 'All notable changes…' paragraph
        // precede the first release and never surface anywhere.
        #expect(document.releases.first?.version == "Unreleased")
        for release in document.releases {
            for paragraph in release.intro {
                #expect(!plain(paragraph).contains("All notable changes"))
            }
        }
    }

    // MARK: - Bullet continuation

    @Test("wrapped bullet continuation lines join with a single space")
    func wrappedBulletJoinsWithSpace() {
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        ### Added

        - A bullet that wraps
          onto a second line
          and a third.
        - A following bullet.
        """)

        let bullets = document.releases[0].sections[0].themes[0].bullets.map(plain)
        #expect(bullets == ["A bullet that wraps onto a second line and a third.", "A following bullet."])
    }

    @Test("a blank line ends a pending bullet; later prose is not appended")
    func blankLineFlushesPendingBullet() {
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        ### Added

        - A complete bullet.

        Stray prose after a blank line.
        """)

        let bullets = document.releases[0].sections[0].themes[0].bullets.map(plain)
        #expect(bullets == ["A complete bullet."])
    }

    // MARK: - newestRelease
}

// MARK: - Version-3 line filter

@MainActor
@Suite("ChangelogDocument version line")
struct ChangelogDocumentVersionLineTests {
    @Test("displayReleases keeps only the version-3 line, in file order")
    func keepsOnlyVersionThree() {
        let document = ChangelogDocument.parse("""
        ## [Unreleased]

        ## [3.1.0] - 2026-10-01

        ### Added

        - Newer.

        ## [3.0.0-alpha.1] - 2026-09-03

        ### Added

        - The rebuild.

        ## [2.0.1] - 2026-01-01

        ### Fixed

        - Old fix.
        """)

        #expect(ChangelogDocument.displayReleases(in: document, majorVersion: 3).map(\.version) == ["3.1.0", "3.0.0-alpha.1"])
    }

    @Test("displayReleases is empty when the document has no 3.x entries")
    func emptyWithoutVersionThree() {
        let document = ChangelogDocument.parse("""
        ## [2.0.1]

        ### Fixed

        - Old fix.
        """)

        #expect(ChangelogDocument.displayReleases(in: document, majorVersion: 3).isEmpty)
    }

    @Test("Links in the notes open only over https; any other link stays as plain text", arguments: [
        "thaw://set?key=x", "file:///etc/hosts", "http://example.com", "floe://run", "javascript:alert",
    ])
    func proseLinksAreHTTPSOnly(url: String) throws {
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        ### Fixed

        - See [the notes](\(url)) and [the site](https://example.com).
        """)
        let block = try #require(document.releases.first?.sections.first?.themes.first?.bullets.first)
        guard case let .text(text) = block else {
            Issue.record("Expected text")
            return
        }
        let links = text.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com")])
        #expect(String(text.characters).contains("the notes"))
    }
}
