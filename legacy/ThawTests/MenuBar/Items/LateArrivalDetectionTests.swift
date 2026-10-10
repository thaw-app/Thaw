//
//  LateArrivalDetectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Pins the identity-quality filter on late-arrival detection.
///
/// With just under half the `sourcePID`s unresolved, every apply still runs
/// (#881). Each resolution flap swaps an item between its resolved and
/// fallback identity, and the unrecorded form reads as a fresh arrival,
/// scheduling another re-sort. The moves land, so no other guard stops it.
@Suite("Late arrival detection")
struct LateArrivalDetectionTests {
    /// The resolved and fallback identities the log showed for the same
    /// items, in pairs.
    private enum Field {
        static let statsResolved = "eu.exelban.Stats:CPU_bar_chart"
        static let statsFallback = "eu.exelban.Stats:eu.exelban.Stats:1"
        static let soundSourceResolved = "com.rogueamoeba.soundsource:Input"
        static let soundSourceFallback = "com.rogueamoeba.soundsource:com.rogueamoeba.soundsource"
    }

    private func item(
        _ namespace: String,
        _ title: String,
        sourcePID: pid_t?
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .string(namespace), title: title),
            windowID: CGWindowID.random(in: 1000 ... 9999),
            sourcePID: sourcePID
        )
    }

    // MARK: - The loop this closes

    /// An unresolved item carries a fallback identity and must not read as an
    /// arrival, even when a profile captured during a flap contains that form.
    @Test("An unresolved item is not a late arrival")
    func unresolvedItemIsNotALateArrival() {
        let items = [item("eu.exelban.Stats", "eu.exelban.Stats:1", sourcePID: nil)]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: items,
            profileIdentifiers: [Field.statsFallback, Field.statsResolved],
            alreadySortedIdentifiers: [Field.statsResolved]
        )
        #expect(arrivals.isEmpty)
    }

    /// The last sort recorded the resolved form, then the same item comes back
    /// under its fallback identity.
    @Test("A resolution flap does not manufacture an arrival")
    func resolutionFlapDoesNotManufactureAnArrival() {
        let flapped = [
            item("eu.exelban.Stats", "eu.exelban.Stats:1", sourcePID: nil),
            item("com.rogueamoeba.soundsource", "com.rogueamoeba.soundsource", sourcePID: nil),
        ]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: flapped,
            profileIdentifiers: [
                Field.statsResolved, Field.statsFallback,
                Field.soundSourceResolved, Field.soundSourceFallback,
            ],
            alreadySortedIdentifiers: [Field.statsResolved, Field.soundSourceResolved]
        )
        #expect(arrivals.isEmpty)
    }

    /// A pass with nothing resolved (as after the settle-end fast restore)
    /// yields no arrivals rather than every item.
    @Test("A pass with nothing resolved yields no arrivals")
    func passWithNothingResolvedYieldsNoArrivals() {
        let items = [
            item("eu.exelban.Stats", "eu.exelban.Stats:1", sourcePID: nil),
            item("com.apple.controlcenter", "", sourcePID: nil),
            item("com.apple.controlcenter", ":1", sourcePID: nil),
        ]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: items,
            profileIdentifiers: Set(items.map(\.uniqueIdentifier)),
            alreadySortedIdentifiers: []
        )
        #expect(arrivals.isEmpty)
    }

    // MARK: - What must still be detected

    /// An app launches after Thaw, resolves cleanly, and is in the profile but
    /// not yet sorted.
    @Test("A resolved, unsorted profile item is a late arrival")
    func resolvedUnsortedProfileItemIsALateArrival() {
        let items = [item("eu.exelban.Stats", "CPU_bar_chart", sourcePID: 4321)]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: items,
            profileIdentifiers: [Field.statsResolved],
            alreadySortedIdentifiers: []
        )
        #expect(arrivals == [Field.statsResolved])
    }

    /// The filter narrows the set rather than suppressing detection.
    @Test("A genuine arrival survives alongside unresolved items")
    func genuineArrivalSurvivesAlongsideUnresolvedItems() {
        let items = [
            item("eu.exelban.Stats", "CPU_bar_chart", sourcePID: 4321),
            item("com.rogueamoeba.soundsource", "com.rogueamoeba.soundsource", sourcePID: nil),
            item("com.apple.controlcenter", ":2", sourcePID: nil),
        ]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: items,
            profileIdentifiers: [
                Field.statsResolved, Field.soundSourceResolved, Field.soundSourceFallback,
            ],
            alreadySortedIdentifiers: [Field.soundSourceResolved]
        )
        #expect(arrivals == [Field.statsResolved])
    }

    /// An item already sorted under its resolved identity is not an arrival.
    @Test("An already-sorted item is not a late arrival")
    func alreadySortedItemIsNotALateArrival() {
        let items = [item("eu.exelban.Stats", "CPU_bar_chart", sourcePID: 4321)]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: items,
            profileIdentifiers: [Field.statsResolved],
            alreadySortedIdentifiers: [Field.statsResolved]
        )
        #expect(arrivals.isEmpty)
    }

    /// An item outside the profile never triggers a profile re-sort.
    @Test("An item outside the profile is not a late arrival")
    func itemOutsideTheProfileIsNotALateArrival() {
        let items = [item("com.example.other", "Item-0", sourcePID: 4321)]
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: items,
            profileIdentifiers: [Field.statsResolved],
            alreadySortedIdentifiers: []
        )
        #expect(arrivals.isEmpty)
    }

    /// Control items are Thaw's own dividers, not profile members, and are
    /// excluded regardless of whether their PID resolved.
    @Test("Control items are never late arrivals")
    func controlItemsAreNeverLateArrivals() {
        let divider = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .string("com.stonerl.Thaw"),
                title: "Thaw.ControlItem.Hidden"
            ),
            windowID: 27481,
            sourcePID: 4321
        )
        let arrivals = MenuBarItemManager.lateArrivingProfileIdentifiers(
            items: [divider],
            profileIdentifiers: [divider.uniqueIdentifier],
            alreadySortedIdentifiers: []
        )
        #expect(arrivals.isEmpty)
    }
}
