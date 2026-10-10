//
//  ChangelogDocumentTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Characterization for ChangelogDocument.parse(_:), the deliberately
/// small Keep-a-Changelog parser behind the What's New sheet. These tests pin
/// the parser's known shape (releases, sections, themes, bullets) and its
/// degradation behavior on input it does not recognize.
@MainActor
@Suite("ChangelogDocument parsing")
struct ChangelogDocumentTests {
    /// The plain-text characters of an AttributedString bullet, for
    /// asserting content independent of inline styling runs.
    private func plain(_ text: AttributedString) -> String {
        String(text.characters)
    }

    /// The plain text of a block, so a prose block and a callout assert the
    /// same way.
    private func plain(_ block: ChangelogDocument.Block) -> String {
        switch block {
        case let .text(text):
            plain(text)
        case let .callout(callout):
            plain(callout)
        }
    }

    /// A callout's parts joined with newlines.
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

    @Test("newestRelease skips an empty [Unreleased] release")
    func newestReleaseSkipsEmptyUnreleased() {
        let document = ChangelogDocument.parse("""
        ## [Unreleased]

        ## [1.2.0]

        ### Fixed

        - The fix.
        """)

        #expect(document.newestRelease?.version == "1.2.0")
    }

    @Test("newestRelease returns [Unreleased] when it has content")
    func newestReleaseKeepsPopulatedUnreleased() {
        let document = ChangelogDocument.parse("""
        ## [Unreleased]

        ### Added

        - Something upcoming.

        ## [1.2.0]

        ### Fixed

        - The fix.
        """)

        #expect(document.newestRelease?.version == "Unreleased")
    }

    @Test("newestRelease is nil for a document with no content at all")
    func newestReleaseNilForEmptyDocument() {
        #expect(ChangelogDocument.parse("").newestRelease == nil)
        #expect(ChangelogDocument.parse("# Changelog\n\nProse only.").newestRelease == nil)
    }

    // MARK: - Inline markdown

    @Test("inline markdown is interpreted; plain characters survive")
    func inlineMarkdownSurvives() {
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        ### Added

        - Supports **bold**, _italic_, `code`, and [links](https://example.com).
        """)

        let bullet = document.releases[0].sections[0].themes[0].bullets[0]
        // The markup characters are consumed by inline parsing; the visible
        // text keeps the words themselves.
        #expect(plain(bullet) == "Supports bold, italic, code, and links.")
    }

    // MARK: - Malformed input degrades sanely

    @Test("bullets before any release header are dropped without crashing")
    func bulletsBeforeAnyReleaseAreDropped() {
        let document = ChangelogDocument.parse("""
        - An orphan bullet.

        ## [1.0.0]

        ### Added

        - A real bullet.
        """)

        #expect(document.releases.count == 1)
        #expect(document.releases[0].intro.isEmpty)
        #expect(document.releases[0].sections[0].themes[0].bullets.map(plain) == ["A real bullet."])
    }

    @Test("a '###' section header before any release is ignored")
    func sectionBeforeAnyReleaseIsIgnored() {
        let document = ChangelogDocument.parse("""
        ### Added

        - Lost bullet.

        ## [1.0.0]

        ### Fixed

        - Kept bullet.
        """)

        #expect(document.releases.count == 1)
        #expect(document.releases[0].sections.map(\.title) == ["Fixed"])
    }

    @Test("a '####' theme with no open section is dropped; the release survives")
    func themeWithoutSectionKeepsRelease() {
        // A theme header before any ### section has nothing to attach to.
        // The parser drops the orphan header but must keep the release; the
        // bullets that follow degrade into the release intro.
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        #### Orphan theme

        - Orphan bullet.

        ## [0.9.0]

        ### Fixed

        - Surviving bullet.
        """)

        #expect(document.releases.map(\.version) == ["1.0.0", "0.9.0"])
        #expect(document.releases[0].sections.isEmpty)
        #expect(document.releases[0].intro.map(plain) == ["Orphan bullet."])
        #expect(document.newestRelease?.version == "1.0.0")
    }

    @Test("headers out of order never crash and unrecognized lines fall away")
    func headersOutOfOrderDegrade() {
        let document = ChangelogDocument.parse("""
        #### Theme first

        ### Section next

        - Homeless bullet.

        ## [1.0.0]

        random prose
        ### Added
        - Attached bullet.
        """)

        #expect(document.releases.count == 1)
        #expect(document.releases[0].version == "1.0.0")
        #expect(document.releases[0].sections.map(\.title) == ["Added"])
        #expect(document.releases[0].sections[0].themes[0].bullets.map(plain) == ["Attached bullet."])
    }

    // MARK: - Release dates

    @Test("a Keep a Changelog date after the version is read; its absence is nil")
    func releaseDates() throws {
        let document = ChangelogDocument.parse("""
        ## [2.0.0] - 2026-09-02
        - Dated.

        ## [1.5.0] -   2026-01-15
        - Dated with extra spaces.

        ## [1.0.0]
        - Undated.

        ## [0.9.0] - not a date
        - Garbage trailer.
        """)

        #expect(document.releases.count == 4)

        let calendar = Calendar(identifier: .gregorian)
        let dated = try #require(document.releases[0].date)
        // The parser reads a release date as a local day.
        let parts = calendar.dateComponents(in: TimeZone.current, from: dated)
        #expect((parts.year, parts.month, parts.day) == (2026, 9, 2))

        let spaced = try #require(document.releases[1].date)
        let spacedParts = calendar.dateComponents(in: TimeZone.current, from: spaced)
        #expect((spacedParts.year, spacedParts.month, spacedParts.day) == (2026, 1, 15))

        #expect(document.releases[2].date == nil)
        #expect(document.releases[2].version == "1.0.0")
        #expect(document.releases[3].date == nil)
        #expect(document.releases[3].version == "0.9.0")
    }

    // MARK: - Intro prose and badges

    @Test("prose ahead of a release's first section is kept as intro; a badge line becomes a badge")
    func introProseAndBadges() throws {
        let document = ChangelogDocument.parse("""
        # Changelog

        Preamble prose that never surfaces.

        ## [1.0.0] - 2026-09-03

        A rebuilt release, written
        across two lines.

        [![On Product Hunt](Badge.svg)](https://example.com/thaw)

        <div>raw html for the repository page</div>

        - An intro bullet.

        ### Added

        Prose inside a section is still dropped.

        - A real bullet.
        """)

        let release = try #require(document.releases.first)
        #expect(release.intro.map(plain) == ["A rebuilt release, written across two lines.", "An intro bullet."])
        #expect(release.badges.count == 1)
        #expect(release.badges.first?.alt == "On Product Hunt")
        #expect(release.badges.first?.imageFileName == "Badge.svg")
        #expect(release.badges.first?.url.absoluteString == "https://example.com/thaw")
        #expect(release.sections[0].themes[0].bullets.map(plain) == ["A real bullet."])
    }
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

        #expect(ChangelogDocument.displayReleases(in: document).map(\.version) == ["3.1.0", "3.0.0-alpha.1"])
    }

    @Test("displayReleases is empty when the document has no 3.x entries")
    func emptyWithoutVersionThree() {
        let document = ChangelogDocument.parse("""
        ## [2.0.1]

        ### Fixed

        - Old fix.
        """)

        #expect(ChangelogDocument.displayReleases(in: document).isEmpty)
    }
}
