//
//  ChangelogDocumentDegradationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawUI

/// The parser on input it does not fully recognize, and what it makes of a
/// release's optional parts: an empty release, stray headers, dates, badges.
@MainActor
@Suite("ChangelogDocument degradation")
struct ChangelogDocumentDegradationTests {
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
        // Inline parsing consumes the markup characters and keeps the words.
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
        // A theme header before any ### section has nothing to attach to, so it's dropped.
        // The release must survive, and the bullets that follow degrade into its intro.
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
}
