//
//  ChangelogDocumentReleasePartsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawUI

/// What the parser makes of a release's optional parts: its date, intro and badges.
@MainActor
@Suite("ChangelogDocument release parts")
struct ChangelogDocumentReleasePartsTests {
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

    @Test("numbered steps in the intro stay separate lines and keep their numbers")
    func numberedStepsStaySeparate() throws {
        let document = ChangelogDocument.parse("""
        ## [3.0.0] - 2026-10-11

        After you update:

        1. Open Settings > Layout and look at **Hiding method**.
        2. If the icon is missing,
           open Settings.

        ### Fixed

        - A real bullet.
        """)

        let release = try #require(document.releases.first)
        #expect(release.intro.map(plain) == [
            "After you update:",
            "1. Open Settings > Layout and look at Hiding method.",
            "2. If the icon is missing, open Settings.",
        ])
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

    @Test(
        "a badge whose link is not https is dropped, and the rest of the release stays",
        arguments: [
            "http://example.com/thaw",
            "file:///etc/passwd",
            "thaw://reset",
            "javascript:alert",
            "/relative/path",
            "https:no-host",
        ]
    )
    func nonHTTPSBadgeIsDropped(url: String) throws {
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        [![Dropped](Dropped.svg)](\(url))

        [![Kept](Kept.svg)](https://example.com/thaw)

        An intro paragraph.
        """)

        let release = try #require(document.releases.first)
        #expect(release.badges.map(\.alt) == ["Kept"])
        #expect(release.intro.map(plain) == ["An intro paragraph."])
    }

    @Test("a badge's https scheme is matched in any case")
    func httpsBadgeSchemeIgnoresCase() throws {
        let document = ChangelogDocument.parse("""
        ## [1.0.0]

        [![Upper](Upper.svg)](HTTPS://example.com/thaw)
        """)

        let release = try #require(document.releases.first)
        #expect(release.badges.map(\.alt) == ["Upper"])
    }
}
