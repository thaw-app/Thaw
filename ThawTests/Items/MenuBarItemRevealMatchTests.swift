//
//  MenuBarItemRevealMatchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins MenuBarItemImageCache.revealMatches(requests:live:). The AX walk names
/// untitled items positionally, so a revealed item can return under its
/// sibling's name; strict identity alone would cache nothing and re-reveal on
/// every Thaw Bar open.
@MainActor
@Suite("Reveal matching")
struct MenuBarItemRevealMatchTests {
    private static func item(
        _ bundleID: String,
        _ title: String,
        windowID: CGWindowID,
        instanceIndex: Int = 0,
        pid: pid_t = 501
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string(bundleID),
                title: title,
                windowID: windowID,
                instanceIndex: instanceIndex
            ),
            windowID: windowID,
            ownerPID: pid,
            sourcePID: pid,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    @Test("An exact identity match wins")
    func exactMatch() {
        let requested = Self.item("com.example.app", "Item-0", windowID: 11)
        let live = Self.item("com.example.app", "Item-0", windowID: 99)

        let matches = MenuBarItemImageCache.revealMatches(requests: [requested], live: [live])

        #expect(matches.count == 1)
        #expect(matches[0]?.windowID == 99)
    }

    /// Two untitled items, one revealed alone: the concealed sibling holds no
    /// slot, so Item-1 returns as Item-0.
    @Test("A lone revealed sibling renamed by the walk still resolves")
    func positionalRenameResolves() {
        let requested = Self.item("com.example.app", "Item-1", windowID: 12, instanceIndex: 1)
        let live = Self.item("com.example.app", "Item-0", windowID: 77)

        let matches = MenuBarItemImageCache.revealMatches(requests: [requested], live: [live])

        #expect(matches[0]?.windowID == 77)
    }

    /// Revealing both members restores the numbering the tags were minted
    /// under, so both resolve strictly and the fallback never runs.
    @Test("Siblings revealed together both match strictly")
    func siblingsRevealedTogether() {
        let first = Self.item("com.example.app", "Item-0", windowID: 12)
        let second = Self.item("com.example.app", "Item-1", windowID: 13, instanceIndex: 1)
        let liveFirst = Self.item("com.example.app", "Item-0", windowID: 77)
        let liveSecond = Self.item("com.example.app", "Item-1", windowID: 78, instanceIndex: 1)

        let matches = MenuBarItemImageCache.revealMatches(
            requests: [first, second],
            live: [liveSecond, liveFirst]
        )

        #expect(matches[0]?.windowID == 77)
        #expect(matches[1]?.windowID == 78)
    }

    /// Two unmatched requests for one app cannot be told apart, and guessing
    /// would file a neighbour's glyph under the wrong tag. An extra reveal is
    /// the cheaper mistake.
    @Test("Ambiguity leaves both unresolved")
    func ambiguousOwnerLeavesUnresolved() {
        let first = Self.item("com.example.app", "Item-3", windowID: 12, instanceIndex: 3)
        let second = Self.item("com.example.app", "Item-4", windowID: 13, instanceIndex: 4)
        let live = Self.item("com.example.app", "Item-0", windowID: 77)

        let matches = MenuBarItemImageCache.revealMatches(
            requests: [first, second],
            live: [live]
        )

        #expect(matches.allSatisfy { $0 == nil })
    }

    /// Two live candidates and one request is the same ambiguity seen from the
    /// other side: the request may belong to either.
    @Test("Two unclaimed live candidates leave the request unresolved")
    func ambiguousLiveCandidatesLeaveUnresolved() {
        let requested = Self.item("com.example.app", "Item-5", windowID: 12, instanceIndex: 5)
        let liveFirst = Self.item("com.example.app", "Item-0", windowID: 77)
        let liveSecond = Self.item("com.example.app", "Item-1", windowID: 78, instanceIndex: 1)

        let matches = MenuBarItemImageCache.revealMatches(
            requests: [requested],
            live: [liveFirst, liveSecond]
        )

        #expect(matches[0] == nil)
    }

    /// A real title is never renumbered, so a title mismatch there is a
    /// different item rather than a renamed one.
    @Test("A named item never falls back to owner scope")
    func namedItemDoesNotFallBack() {
        let requested = Self.item("com.example.app", "Sync", windowID: 12)
        let live = Self.item("com.example.app", "Vault", windowID: 77)

        let matches = MenuBarItemImageCache.revealMatches(requests: [requested], live: [live])

        #expect(matches[0] == nil)
    }

    /// The same app running twice is two owners; a reveal in one process must
    /// not resolve against the other's item.
    @Test("A different process is not the same owner")
    func differentPIDDoesNotMatch() {
        let requested = Self.item("com.example.app", "Item-1", windowID: 12, instanceIndex: 1, pid: 501)
        let live = Self.item("com.example.app", "Item-0", windowID: 77, pid: 902)

        let matches = MenuBarItemImageCache.revealMatches(requests: [requested], live: [live])

        #expect(matches[0] == nil)
    }

    /// A settled member keeps its claim when the next poll offers the whole
    /// batch again, so the fallback cannot hand its live item to a sibling.
    @Test("A claimed live item is not offered to a second request")
    func claimIsExclusive() {
        let settled = Self.item("com.example.app", "Item-0", windowID: 12)
        let pending = Self.item("com.example.app", "Item-9", windowID: 13, instanceIndex: 9)
        let live = Self.item("com.example.app", "Item-0", windowID: 77)

        let matches = MenuBarItemImageCache.revealMatches(
            requests: [settled, pending],
            live: [live]
        )

        #expect(matches[0]?.windowID == 77)
        #expect(matches[1] == nil)
    }

    /// Nothing revealed at all stays nothing: an absent item must not borrow
    /// another app's glyph.
    @Test("An unrelated live item never answers a request")
    func unrelatedOwnerNeverMatches() {
        let requested = Self.item("com.example.app", "Item-1", windowID: 12, instanceIndex: 1)
        let live = Self.item("com.other.app", "Item-0", windowID: 77)

        let matches = MenuBarItemImageCache.revealMatches(requests: [requested], live: [live])

        #expect(matches[0] == nil)
    }
}
