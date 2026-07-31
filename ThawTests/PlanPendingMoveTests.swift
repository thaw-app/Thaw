//
//  PlanPendingMoveTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Characterization tests for PendingLedger.planPendingMove.
///
/// Pins down the per-entry decision logic used by relocatePendingItems:
/// actively-shown short-circuit, waitForRelaunch sentinel handling,
/// item-already-hidden cleanup, destination resolution (stored neighbor →
/// fallback neighbor → section boundary), and itemNotPresent skipping.
///
/// Coordinate convention: hidden divider at x=400, width=10. Items in
/// "visible" sit at x >= 410. Items in "hidden" sit at x < 400.
@Suite("Plan pending move")
struct PlanPendingMoveTests {
    // MARK: - Helpers

    private let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)

    private func appTag(_ bundleID: String, _ title: String, _ instanceIndex: Int = 0) -> MenuBarItemTag {
        .appItem(bundleID: bundleID, title: title, instanceIndex: instanceIndex)
    }

    private func visibleItem(
        bundleID: String,
        title: String,
        windowID: CGWindowID,
        x: CGFloat = 500
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: appTag(bundleID, title),
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22)
        )
    }

    private func hiddenItem(
        bundleID: String,
        title: String,
        windowID: CGWindowID,
        x: CGFloat = 200
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: appTag(bundleID, title),
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22)
        )
    }

    private func pair() -> MenuBarItemManager.ControlItemPair {
        MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: hiddenBounds,
            alwaysHiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
    }

    // MARK: - Scenarios

    /// A standard pending entry for a visible item produces a move to the
    /// section boundary (no stored neighbor, no fallback).
    @Test("A standard entry for a visible item falls back to the section boundary")
    func standardEntryVisibleItemFallsBackToSectionBoundary() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 800)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case let .move(movedItem, destination) = decision {
            #expect(movedItem.windowID == 800)
            if case let .leftOfItem(neighbor) = destination {
                #expect(neighbor.tag == .hiddenControlItem,
                        "section-boundary fallback should target the hidden control item")
            } else {
                Issue.record("expected .leftOfItem, got \(destination)")
            }
        } else {
            Issue.record("expected .move, got \(decision)")
        }
    }

    /// A pending entry whose item is already in the hidden section
    /// produces .clearEntry — no move needed.
    @Test("A standard entry whose item is already hidden clears the entry")
    func standardEntryAlreadyHiddenClearsEntry() {
        let item = hiddenItem(bundleID: "com.example.app", title: "Status", windowID: 801)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case .clearEntry = decision {
            // expected
        } else {
            Issue.record("expected .clearEntry, got \(decision)")
        }
    }

    /// When the item referenced by the pending entry is not in the current
    /// items list, the planner emits .skip(.itemNotPresent) — the entry
    /// stays in the dict for the next launch.
    @Test("An entry whose item is not present skips")
    func itemNotPresentSkips() {
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: "com.gone.app:Status",
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        #expect(decision == .skip(reason: .itemNotPresent))
    }

    /// waitForRelaunch sentinel with the same windowID skips with
    /// .waitForRelaunchActive.
    @Test("A waitForRelaunch sentinel with the same windowID skips")
    func waitForRelaunchSameWindowIDSkips() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 802)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .waitForRelaunch(windowID: 802, section: .hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        #expect(decision == .skip(reason: .waitForRelaunchActive))
    }

    /// waitForRelaunch sentinel with a new windowID (app relaunched)
    /// promotes the entry. The orchestrator persists the change and
    /// re-runs the planner.
    @Test("A waitForRelaunch sentinel with a new windowID promotes the entry")
    func waitForRelaunchNewWindowIDPromotes() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 803)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .waitForRelaunch(windowID: 999, section: .hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case let .promoteWaitForRelaunch(section) = decision {
            #expect(section == .hidden)
        } else {
            Issue.record("expected .promoteWaitForRelaunch, got \(decision)")
        }
    }

    /// An entry whose tag is currently in activelyShownTags skips with
    /// .activelyShown — the rehide flow owns this item.
    @Test("An actively shown entry is excluded")
    func activelyShownExclusion() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 804)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [item.tag.tagIdentifier],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        #expect(decision == .skip(reason: .activelyShown))
    }

    /// An entry whose recorded section is .visible produces .clearEntry —
    /// there's no hidden destination to restore to.
    @Test("An entry recorded for the visible section short-circuits to clear")
    func visibleSectionShortCircuitsToClear() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 805)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.visible)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case .clearEntry = decision {
            // expected
        } else {
            Issue.record("expected .clearEntry, got \(decision)")
        }
    }

    /// A stored neighbor destination takes precedence over the fallback
    /// neighbor and the section boundary.
    @Test("A stored neighbor takes precedence over the fallbacks")
    func storedNeighborTakesPrecedence() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 806, x: 500)
        let neighbor = visibleItem(bundleID: "com.example.app", title: "Other", windowID: 807, x: 600)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item, neighbor],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [
                    item.tag.tagIdentifier: [
                        "neighbor": neighbor.tag.tagIdentifier,
                        "position": "left",
                    ],
                ],
                fallbackNeighbors: [:]
            )
        )

        if case let .move(_, destination) = decision,
           case let .leftOfItem(target) = destination
        {
            #expect(target.windowID == 807,
                    "stored neighbor should win over the section-boundary fallback")
        } else {
            Issue.record("expected .move(.leftOfItem(neighbor)), got \(decision)")
        }
    }
}
