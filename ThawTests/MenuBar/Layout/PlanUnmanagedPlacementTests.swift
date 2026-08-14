//
//  PlanUnmanagedPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for LayoutSolver.planUnmanagedPlacement.
///
/// Pins down the placement decision for items present in the live menu
/// bar but not covered by a profile spec. Saved positions win; otherwise
/// the user's NewItemsPlacement preference applies; otherwise fall back
/// to the section default.
@Suite("Plan unmanaged placement")
struct PlanUnmanagedPlacementTests {
    /// All unmanaged items have saved positions → all placements are .saved.
    @Test("Unmanaged items with saved positions all get saved placements")
    func allSavedReturnsSavedPlacements() {
        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "com.b.app:B"],
            "hidden": ["com.c.app:C"],
        ]
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.a.app:A", "com.c.app:C"],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: Set(["com.a.app:A", "com.c.app:C"])
        )

        #expect(result["com.a.app:A"] == .saved(section: .visible, index: 0))
        #expect(result["com.c.app:C"] == .saved(section: .hidden, index: 0))
    }

    /// No saved positions, no anchor → all .newItemDefault in the
    /// new-items section.
    @Test("An unseen item with no anchor lands in the new-items section")
    func allUnseenReturnsNewItemDefault() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status"]
        )

        #expect(result["com.new.app:Status"] == .newItemDefault(section: .hidden))
    }

    /// Mixed: one saved, one unseen → correct per-uid placements.
    @Test("A mix of saved and unseen items gets per-uid placements")
    func mixedSavedAndUnseen() {
        let saved: [String: [String]] = [
            "visible": ["com.known.app:Status"],
        ]
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.known.app:Status", "com.new.app:Status"],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: ["com.known.app:Status", "com.new.app:Status"]
        )

        #expect(result["com.known.app:Status"] == .saved(section: .visible, index: 0))
        #expect(result["com.new.app:Status"] == .newItemDefault(section: .hidden))
    }

    /// Multi-instance: only one instance is saved, the other instance is
    /// the unmanaged one. baseID fallback gives the unmanaged instance
    /// the saved position (treating them as fungible).
    @Test("A different instance index falls back to the saved baseID slot")
    func multiInstanceBaseIDFallback() {
        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status"], // saved without :N suffix
        ]
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        // A different instance index appears. Exact match fails, baseID
        // match succeeds → .saved.
        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.example.app:Status:7"],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: ["com.example.app:Status:7"]
        )

        #expect(
            result["com.example.app:Status:7"] == .saved(section: .hidden, index: 0),
            "unmanaged instance with matching baseID should use the saved slot"
        )
    }

    /// NewItemsPlacement configured with an anchor that's currently
    /// present → .newItemAnchored returned for an unseen item.
    @Test("A present anchor produces an anchored placement")
    func anchorPlacementWhenAnchorPresent() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.spotlight.app:Anchor",
            relation: .leftOfAnchor
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status", "com.spotlight.app:Anchor"]
        )

        #expect(
            result["com.new.app:Status"] == .newItemAnchored(
                section: .visible,
                anchorUID: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )
    }

    /// NewItemsPlacement anchor configured but anchor item is absent from
    /// the current menu bar → fall back to .newItemDefault.
    @Test("An absent anchor falls back to the section default")
    func anchorAbsentFallsBackToDefault() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.absent.app:Anchor",
            relation: .leftOfAnchor
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status"]
        )

        #expect(result["com.new.app:Status"] == .newItemDefault(section: .visible))
    }

    // MARK: Volatile-title identities (#815)

    /// A volatile-title owner is saved under whatever its title was at the
    /// time and carries a different one now, so the exact lookup misses. The
    /// baseID fallback misses too, because for these owners the title *is*
    /// the volatile part, so `namespace:title` differs just as the full
    /// identifier does. Without a canonical comparison the item arrives here
    /// with no saved position and is placed by newItemDefault — dropping the
    /// lyrics back into the hidden section the user dragged them out of.
    @Test("A canonicalized identity reuses its saved position")
    func canonicalIdentityReusesSavedPosition() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "\(owner):a lyric from when this was saved"],
        ]
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let liveUID = "\(owner):an entirely different lyric"

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: [liveUID],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: Set([liveUID])
        )

        #expect(result[liveUID] == .saved(section: .visible, index: 1))
        #expect(result[liveUID] != .newItemDefault(section: .hidden))
    }

    /// The same for the metric owner the canonicalizer was built for.
    @Test("A changed metric reading reuses its saved position")
    func changedMetricReusesSavedPosition() {
        let owner = MenuBarItemTag.iStatMenusStatusBundleID
        let saved = ["hidden": ["\(owner):CPU 12%"]]
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let liveUID = "\(owner):CPU 87%"

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: [liveUID],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: Set([liveUID])
        )

        #expect(result[liveUID] == .saved(section: .hidden, index: 0))
    }

    /// Canonicalization preserves the instance index, so two items from one
    /// opaque owner must still resolve to their own saved entries rather than
    /// both collapsing onto the first.
    @Test("Instance indexes still separate two items from one owner")
    func instanceIndexesResolveSeparately() {
        let owner = MenuBarItemTag.lyricsXBundleID
        let saved: [String: [String]] = [
            "visible": ["\(owner):first"],
            "hidden": ["\(owner):second:1"],
        ]
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let liveZero = "\(owner):now playing"
        let liveOne = "\(owner):also playing:1"

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: [liveZero, liveOne],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: Set([liveZero, liveOne])
        )

        #expect(result[liveZero] == .saved(section: .visible, index: 0))
        #expect(result[liveOne] == .saved(section: .hidden, index: 0))
    }
}
