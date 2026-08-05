//
//  MenuBarItemTagCanonicalizationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

// MARK: - Volatile-Title Canonicalization Tests

@Suite("Menu bar item tag canonicalization")
struct MenuBarItemTagCanonicalizationTests {
    private let prefix = MenuBarItemTag.iStatMenusStatusBundleID

    // MARK: - canonicalMetricTitle

    @Test("Integers and decimals collapse to a placeholder")
    func collapsesIntegersAndDecimals() {
        #expect(MenuBarItemTag.canonicalMetricTitle("CPU 12%") == "CPU #%")
        #expect(MenuBarItemTag.canonicalMetricTitle("CPU 43%") == "CPU #%")
        #expect(MenuBarItemTag.canonicalMetricTitle("Load 1.75") == "Load #")
        #expect(MenuBarItemTag.canonicalMetricTitle("Load 1,75") == "Load #")
        #expect(MenuBarItemTag.canonicalMetricTitle("Temp -4°") == "Temp #°")
    }

    /// The point of the unit normalization: a rate that crosses a magnitude
    /// boundary must not re-key the item.
    @Test("Byte units normalize across magnitudes")
    func normalizesByteUnitsAcrossMagnitudes() {
        let fast = MenuBarItemTag.canonicalMetricTitle("3.4 MB/s")
        let slow = MenuBarItemTag.canonicalMetricTitle("918 KB/s")
        #expect(fast == slow)

        #expect(
            MenuBarItemTag.canonicalMetricTitle("12 GB")
                == MenuBarItemTag.canonicalMetricTitle("512 MB")
        )
    }

    @Test("Non-numeric titles stay distinguishable")
    func leavesNonNumericTitlesDistinguishable() {
        #expect(MenuBarItemTag.canonicalMetricTitle("CPU") == "CPU")
        #expect(
            MenuBarItemTag.canonicalMetricTitle("CPU 12%")
                != MenuBarItemTag.canonicalMetricTitle("Network 12%")
        )
    }

    // MARK: - canonicalPersistentIdentifier

    @Test("Identifiers owned by anything else are left alone")
    func isANoOpForOtherOwners() {
        for identifier in [
            "com.apple.controlcenter:WiFi",
            "com.example.app:Battery 42%",
            "controlCenter:Item-3:1",
            "",
        ] {
            #expect(MenuBarItemTag.canonicalPersistentIdentifier(identifier) == identifier)
        }
    }

    @Test("Samples of the same item collapse to one identifier")
    func collapsesSamplesOfTheSameItem() {
        let first = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%")
        let second = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 43%")

        #expect(first == second)
        #expect(first == "\(prefix):CPU #%")
    }

    @Test("The instance index survives canonicalization")
    func preservesInstanceIndex() {
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:2")
                == "\(prefix):CPU #%:2"
        )
        // Distinct instances of the same metric stay distinct.
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:2")
                != MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):CPU 12%:3")
        )
    }

    /// A colon-bearing title whose trailing segment is not a number is part of
    /// the title, not an instance index.
    @Test("A non-numeric trailing segment is treated as part of the title")
    func treatsNonNumericTrailingSegmentAsTitle() {
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):Disk:Macintosh HD 88%")
                == "\(prefix):Disk:Macintosh HD #%"
        )
    }

    @Test("Canonicalization is idempotent")
    func isIdempotent() {
        let once = MenuBarItemTag.canonicalPersistentIdentifier("\(prefix):Net 3.4 MB/s")
        let twice = MenuBarItemTag.canonicalPersistentIdentifier(once)
        #expect(once == twice)
    }

    // MARK: - canonicalPersistentIdentifiers

    @Test("Volatile duplicates are deduped in order")
    func dedupesVolatileDuplicatesPreservingOrder() {
        let result = MenuBarItemTag.canonicalPersistentIdentifiers([
            "com.apple.controlcenter:WiFi",
            "\(prefix):CPU 12%",
            "\(prefix):CPU 43%",
            "\(prefix):Net 918 KB/s",
            "com.example.app:Clock",
        ])

        #expect(result == [
            "com.apple.controlcenter:WiFi",
            "\(prefix):CPU #%",
            "\(prefix):Net # B/s",
            "com.example.app:Clock",
        ])
    }

    @Test("Distinct owners stay separate")
    func keepsDistinctOwnersSeparate() {
        let result = MenuBarItemTag.canonicalPersistentIdentifiers([
            "\(prefix):CPU 12%",
            "\(prefix):Memory 12%",
        ])
        #expect(result.count == 2)
    }

    // MARK: - Opaque titles (LyricsX, #815)

    /// LyricsX titles its menu bar item with the lyric line on screen, so
    /// consecutive titles share nothing at all. Every song change minted a
    /// fresh identifier, the item read as a brand-new arrival, and Thaw
    /// filed it under the new-items section — moving the lyrics back into
    /// hidden however many times the user dragged them out (#815).
    @Test("Lyric titles collapse to a single identifier")
    func lyricTitlesCollapse() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let first = MenuBarItemTag.canonicalPersistentIdentifier("\(owner):I walked through the door")
        let second = MenuBarItemTag.canonicalPersistentIdentifier("\(owner):and then the music stopped")

        #expect(first == second)
        #expect(first == "\(owner):\(MenuBarItemTag.opaqueTitle)")
    }

    /// The metric canonicalizer would not have helped here: it collapses
    /// digits, and a lyric has none. This is why the owner needed its own
    /// title shape rather than an entry in the existing allowlist.
    @Test("The metric canonicalizer alone would not collapse lyrics")
    func metricCanonicalizerIsInsufficientForLyrics() {
        let a = MenuBarItemTag.canonicalMetricTitle("I walked through the door")
        let b = MenuBarItemTag.canonicalMetricTitle("and then the music stopped")
        #expect(a != b)
    }

    /// An instance index is identity, not title, so it survives the collapse.
    /// With the title gone it is the only thing separating two items from the
    /// same opaque owner.
    @Test("The instance index survives an opaque collapse")
    func opaqueCollapsePreservesInstanceIndex() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let zero = MenuBarItemTag.canonicalPersistentIdentifier("\(owner):some lyric")
        let one = MenuBarItemTag.canonicalPersistentIdentifier("\(owner):another lyric:1")

        #expect(one == "\(owner):\(MenuBarItemTag.opaqueTitle):1")
        #expect(zero != one)
    }

    /// A lyric containing a colon must not be mistaken for an instance index.
    @Test("A colon inside a lyric is not read as an instance index")
    func colonInLyricIsNotAnInstanceIndex() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier("\(owner):Chapter: the end")
        #expect(identifier == "\(owner):\(MenuBarItemTag.opaqueTitle)")
    }

    /// Adding an owner must not have widened the net. Everything outside the
    /// allowlist still passes through untouched, including apps whose titles
    /// happen to look volatile.
    @Test("Unlisted owners are still untouched")
    func unlistedOwnersAreUntouched() {
        for identifier in [
            "com.apple.controlcenter:WiFi",
            "net.cozic.joplin-desktop:Item-0",
            "com.example.player:Now Playing — Some Song",
            "ddddxxx.LyricsXHelper:Item-0",
        ] {
            #expect(MenuBarItemTag.canonicalPersistentIdentifier(identifier) == identifier)
        }
    }

    /// The saved layout accumulated one entry per lyric ever displayed.
    /// Canonicalizing collapses that history to a single key.
    @Test("A layout polluted with per-lyric entries collapses to one key")
    func pollutedLayoutCollapses() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let polluted = (0 ..< 40).map { "\(owner):lyric line number \($0)" }
        let canonical = MenuBarItemTag.canonicalPersistentIdentifiers(polluted)
        #expect(canonical == ["\(owner):\(MenuBarItemTag.opaqueTitle)"])
    }
}
