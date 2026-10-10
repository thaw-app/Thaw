//
//  PlanUnmanagedPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// LayoutSolver.planUnmanagedPlacement for items outside the profile: saved
/// positions win, then NewItemsPlacement, then the section default.
@Suite("Plan unmanaged placement")
struct PlanUnmanagedPlacementTests {
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

    /// Only one instance is saved; the baseID fallback treats instances as fungible.
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

        // The exact match fails; the baseID match succeeds.
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

    /// A helper-namespace anchor matches the live item and names its live UID.
    @Test("A canonicalized anchor matches its live item")
    func canonicalizedAnchorMatchesLiveItem() {
        let placement = MenuBarItemManager.NewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "at.obdev.littlesnitch.agent:Item-0",
            relation: .leftOfAnchor
        )
        let liveAnchor = "at.obdev.littlesnitch:Item-0"

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status", liveAnchor]
        )

        #expect(
            result["com.new.app:Status"] == .newItemAnchored(
                section: .visible,
                anchorUID: liveAnchor,
                relation: .leftOfAnchor
            )
        )
    }

    // MARK: Volatile-title identities (#815)

    /// A volatile-title owner's title is the volatile part, so both the exact and
    /// baseID lookups miss. Without canonical comparison the lyrics land back in
    /// the hidden section the user dragged them out of.
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

    /// The same for the metric owner.
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

    /// Canonicalization keeps the instance index, so two items from one owner keep their own entries.
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
