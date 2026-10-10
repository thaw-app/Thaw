//
//  RevealSettleAdvanceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins MenuBarItemImageCache.advanceRevealSettle(settled:previous:current:hasStable:),
/// the single-poll step that waitForRevealedItems repeats until a revealed
/// group's bounds stop moving.
///
/// A fixed sleep can capture mid-recomposite and leave always-hidden items
/// blank indefinitely, so the settle step is locked here.
@Suite("Reveal settle advance")
struct RevealSettleAdvanceTests {
    private static func item(
        _ bundleID: String,
        _ title: String,
        x: CGFloat,
        windowID: CGWindowID = 11
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: .string(bundleID),
                title: title,
                windowID: windowID,
                instanceIndex: 0
            ),
            windowID: windowID,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    private static func stable(_ before: CGRect, _ after: CGRect) -> Bool {
        MenuBarItemImageCache.hasStableCaptureBounds(before: before, after: after)
    }

    // MARK: - First poll

    @Test("First poll never settles: a stable pair needs two sightings")
    func firstPollNeverSettles() {
        let a = Self.item("com.example.a", "Item-0", x: 100)
        let current = [a.uniqueIdentifier: a]

        let result = MenuBarItemImageCache.advanceRevealSettle(
            settled: [:],
            previous: [:],
            current: current,
            hasStable: Self.stable
        )

        #expect(result.settled.isEmpty)
        // The current sighting is recorded as the previous for the next poll.
        #expect(result.previous[a.uniqueIdentifier] == a)
    }

    // MARK: - Second poll

    @Test("A second sighting with unchanged bounds settles")
    func secondSightingStableSettles() {
        let a = Self.item("com.example.a", "Item-0", x: 100)
        let current = [a.uniqueIdentifier: a]

        let result = MenuBarItemImageCache.advanceRevealSettle(
            settled: [:],
            previous: [a.uniqueIdentifier: a],
            current: current,
            hasStable: Self.stable
        )

        #expect(result.settled[a.uniqueIdentifier] == a)
        // Previous is untouched once settled: a settled item keeps its claim.
        #expect(result.previous[a.uniqueIdentifier] == a)
    }

    @Test("A second sighting with moved bounds does not settle")
    func secondSightingMovedDoesNotSettle() {
        let before = Self.item("com.example.a", "Item-0", x: 100)
        let after = Self.item("com.example.a", "Item-0", x: 140)
        let current = [after.uniqueIdentifier: after]

        let result = MenuBarItemImageCache.advanceRevealSettle(
            settled: [:],
            previous: [before.uniqueIdentifier: before],
            current: current,
            hasStable: Self.stable
        )

        #expect(result.settled.isEmpty)
        // The moved sighting becomes the new previous, so the next stable
        // sighting is measured against the moved position, not the old one.
        #expect(result.previous[after.uniqueIdentifier] == after)
    }

    // MARK: - Mixed group

    @Test("A settled item keeps its claim and is not re-settled against a mover")
    func settledItemKeepsClaim() {
        let stable = Self.item("com.example.a", "Item-0", x: 100)
        let moverBefore = Self.item("com.example.b", "Item-0", x: 200)
        let moverAfter = Self.item("com.example.b", "Item-0", x: 240)
        let current = [
            stable.uniqueIdentifier: stable,
            moverAfter.uniqueIdentifier: moverAfter,
        ]

        let result = MenuBarItemImageCache.advanceRevealSettle(
            settled: [stable.uniqueIdentifier: stable],
            previous: [
                stable.uniqueIdentifier: stable,
                moverBefore.uniqueIdentifier: moverBefore,
            ],
            current: current,
            hasStable: Self.stable
        )

        // The already-settled item is untouched (kept as-is).
        #expect(result.settled[stable.uniqueIdentifier] == stable)
        // The mover has not settled yet.
        #expect(result.settled[moverAfter.uniqueIdentifier] == nil)
        #expect(result.previous[moverAfter.uniqueIdentifier] == moverAfter)
    }

    @Test("An item missing from the current poll clears its previous sighting")
    func missingItemClearsPrevious() {
        let a = Self.item("com.example.a", "Item-0", x: 100)

        let result = MenuBarItemImageCache.advanceRevealSettle(
            settled: [:],
            previous: [a.uniqueIdentifier: a],
            current: [:],
            hasStable: Self.stable
        )

        #expect(result.settled.isEmpty)
        // With no current sighting the prior one is dropped, not carried into
        // a later comparison.
        #expect(result.previous[a.uniqueIdentifier] == nil)
    }

    @Test("A missing item does not un-settle a member that already settled")
    func missingItemDoesNotUnsettle() {
        let a = Self.item("com.example.a", "Item-0", x: 100)

        let result = MenuBarItemImageCache.advanceRevealSettle(
            settled: [a.uniqueIdentifier: a],
            previous: [a.uniqueIdentifier: a],
            current: [:],
            hasStable: Self.stable
        )

        #expect(result.settled[a.uniqueIdentifier] == a)
    }
}
