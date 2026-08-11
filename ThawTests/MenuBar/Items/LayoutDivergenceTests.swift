//
//  LayoutDivergenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/layoutDivergesFromSaved(candidates:sectionLookup:hiddenBounds:alwaysHiddenBounds:overflowExemptUIDs:activelyShownTags:)``,
/// the second of `applySavedLayout`'s two triggers and the one that fires on
/// ambient drift rather than on items coming and going.
///
/// The rule decides whether a bulk apply is dispatched at all, and the only
/// gate between that dispatch and the user's bar is the open-menu probe. When
/// the probe returns a false negative — which #924's logs show it doing on
/// nearly every call, bailing at "no candidate menu windows on screen" — a
/// divergence reported here becomes items moving under an open menu.
@Suite("Layout divergence")
struct LayoutDivergenceTests {
    /// Always-hidden divider at 100–120, hidden divider at 200–220. An item is
    /// visible at minX ≥ 220, hidden between 120 and 200, always-hidden below
    /// 100.
    private let hiddenBounds = CGRect(x: 200, y: 0, width: 20, height: 22)
    private let alwaysHiddenBounds = CGRect(x: 100, y: 0, width: 20, height: 22)

    private func candidate(_ identifier: String, x: CGFloat) -> MenuBarItemManager.DivergenceCandidate {
        .init(
            tagIdentifier: identifier,
            uniqueIdentifier: identifier,
            bounds: CGRect(x: x, y: 0, width: 20, height: 22)
        )
    }

    private func lookup(
        _ pairs: [String: MenuBarSection.Name]
    ) -> (exact: [String: MenuBarSection.Name], unambiguousBase: [String: MenuBarSection.Name]) {
        (exact: pairs, unambiguousBase: [:])
    }

    private func diverges(
        candidates: [MenuBarItemManager.DivergenceCandidate],
        saved: [String: MenuBarSection.Name],
        overflowExemptUIDs: Set<String> = [],
        activelyShownTags: Set<String> = []
    ) -> Bool {
        MenuBarItemManager.layoutDivergesFromSaved(
            candidates: candidates,
            sectionLookup: lookup(saved),
            hiddenBounds: hiddenBounds,
            alwaysHiddenBounds: alwaysHiddenBounds,
            overflowExemptUIDs: overflowExemptUIDs,
            activelyShownTags: activelyShownTags
        )
    }

    @Test("A settled bar does not diverge")
    func settledBarDoesNotDiverge() {
        #expect(
            !diverges(
                candidates: [
                    candidate("eu.exelban.Stats", x: 300),
                    candidate("leits.MeetingBar", x: 140),
                    candidate("us.zoom.xos", x: 50),
                ],
                saved: [
                    "eu.exelban.Stats": .visible,
                    "leits.MeetingBar": .hidden,
                    "us.zoom.xos": .alwaysHidden,
                ]
            )
        )
    }

    @Test("An item sitting outside its saved section diverges")
    func driftedItemDiverges() {
        #expect(
            diverges(
                candidates: [candidate("leits.MeetingBar", x: 300)],
                saved: ["leits.MeetingBar": .hidden]
            )
        )
    }

    /// An item with no saved section has nothing to diverge from.
    @Test("An unsaved item is ignored")
    func unsavedItemIsIgnored() {
        #expect(!diverges(candidates: [candidate("com.example.new", x: 300)], saved: ["leits.MeetingBar": .hidden]))
    }

    @Test("An empty saved order never diverges")
    func emptySavedOrderNeverDiverges() {
        #expect(!diverges(candidates: [candidate("leits.MeetingBar", x: 300)], saved: [:]))
    }

    // MARK: Temporarily shown items (#924)

    /// The regression. Thaw moved this item into the visible section itself in
    /// order to show it, so its position is not drift — it is the feature
    /// working. Reporting it dispatches a bulk apply that drags the item home
    /// under the menu the user just opened.
    @Test("An item Thaw is temporarily showing does not diverge")
    func temporarilyShownItemDoesNotDiverge() {
        #expect(
            !diverges(
                candidates: [candidate("leits.MeetingBar", x: 300)],
                saved: ["leits.MeetingBar": .hidden],
                activelyShownTags: ["leits.MeetingBar"]
            )
        )
    }

    /// The exemption is per item, not a blanket suppression: a genuine drift
    /// elsewhere on the bar still has to be seen while something is shown.
    @Test("A temporarily shown item does not mask another item's drift")
    func temporarilyShownItemDoesNotMaskOtherDrift() {
        #expect(
            diverges(
                candidates: [
                    candidate("leits.MeetingBar", x: 300),
                    candidate("us.zoom.xos", x: 300),
                ],
                saved: [
                    "leits.MeetingBar": .hidden,
                    "us.zoom.xos": .alwaysHidden,
                ],
                activelyShownTags: ["leits.MeetingBar"]
            )
        )
    }

    /// The exemption keys on the tag identifier, which survives the window ID
    /// changes a move produces, so it still matches after the show.
    @Test("The exemption is keyed on the tag identifier, not the window")
    func exemptionIsKeyedOnTagIdentifier() {
        let shown = MenuBarItemManager.DivergenceCandidate(
            tagIdentifier: "leits.MeetingBar",
            uniqueIdentifier: "leits.MeetingBar:1",
            bounds: CGRect(x: 300, y: 0, width: 20, height: 22)
        )
        #expect(
            !diverges(
                candidates: [shown],
                saved: ["leits.MeetingBar:1": .hidden],
                activelyShownTags: ["leits.MeetingBar"]
            )
        )
    }

    // MARK: Notch overflow exemptions

    /// Unchanged behaviour, pinned because the exemption moved from a derived
    /// flag inside the loop to a set passed in by the caller.
    @Test("An ejected item resting in hidden is exempt")
    func ejectedItemInHiddenIsExempt() {
        #expect(
            !diverges(
                candidates: [candidate("eu.exelban.Stats", x: 140)],
                saved: ["eu.exelban.Stats": .visible],
                overflowExemptUIDs: ["eu.exelban.Stats"]
            )
        )
    }

    /// An ejected item that drifted somewhere other than hidden is genuine
    /// drift, and the caller passes an empty set when the feature is off or the
    /// active display has no notch.
    @Test("The overflow exemption only covers hidden")
    func overflowExemptionOnlyCoversHidden() {
        #expect(
            diverges(
                candidates: [candidate("eu.exelban.Stats", x: 50)],
                saved: ["eu.exelban.Stats": .visible],
                overflowExemptUIDs: ["eu.exelban.Stats"]
            )
        )
    }
}
