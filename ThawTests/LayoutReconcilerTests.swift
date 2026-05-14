//
//  LayoutReconcilerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for LayoutReconciler, the thin composition
/// layer over the LayoutSolver planners.
///
/// Pins down: cross-section precedence over within-section in
/// nextRestoreMove, no-op when neither planner has work, and
/// unmanagedPlacementPlan honoring saved positions over NewItems
/// fallback.
final class LayoutReconcilerTests: XCTestCase {
    // MARK: - Helpers

    private func item(
        bundleID: String,
        title: String,
        windowID: CGWindowID
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundleID, title: title),
            windowID: windowID
        )
    }

    private func makeObserved(
        items: [MenuBarItem],
        sectionByWindowID: [CGWindowID: MenuBarSection.Name]
    ) -> ObservedLayout {
        ObservedLayout(
            items: items,
            controlItems: MenuBarItemManager.ControlItemPair.fixture(
                hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22),
                alwaysHiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
            ),
            sectionByWindowID: sectionByWindowID,
            activelyShownTags: []
        )
    }

    private func placement(
        section: String = "hidden",
        anchor: String? = nil,
        relation: MenuBarItemManager.NewItemsPlacement.Relation = .sectionDefault
    ) -> MenuBarItemManager.NewItemsPlacement {
        MenuBarItemManager.NewItemsPlacement(
            sectionKey: section,
            anchorIdentifier: anchor,
            relation: relation
        )
    }

    // MARK: - nextRestoreMove

    /// Cross-section mismatch returns a .crossSection move; the
    /// within-section planner is not consulted because the cross-
    /// section planner short-circuits.
    func testCrossSectionPrecedence() {
        let stray = item(bundleID: "com.example.app", title: "Status", windowID: 200)
        let desired = DesiredLayout.fromSavedSectionOrder(
            ["hidden": ["com.example.app:Status"]],
            newItemsPlacement: placement()
        )
        let observed = makeObserved(
            items: [stray],
            sectionByWindowID: [stray.windowID: .visible]
        )

        let move = LayoutReconciler.nextRestoreMove(
            desired: desired,
            observed: observed,
            hasAlwaysHiddenSection: true
        )

        if case .crossSection(let rebalance) = move {
            XCTAssertEqual(rebalance.fromSection, .visible)
            XCTAssertEqual(rebalance.toSection, .hidden)
            XCTAssertEqual(rebalance.item.windowID, 200)
        } else {
            XCTFail("expected .crossSection move, got \(String(describing: move))")
        }
    }

    /// When cross-section counts match but intra-section order has
    /// drifted, the within-section planner fires.
    func testWithinSectionAfterCrossSectionNil() {
        let a = item(bundleID: "com.a.app", title: "A", windowID: 1010)
        let b = item(bundleID: "com.b.app", title: "B", windowID: 1011)

        // Both items in visible. Saved order says [A, B], current order
        // (by minX) puts B before A.
        let aLeftItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.a.app", title: "A"),
            windowID: 1010,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let bRightItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.b.app", title: "B"),
            windowID: 1011,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22)
        )

        let desired = DesiredLayout.fromSavedSectionOrder(
            ["visible": ["com.a.app:A", "com.b.app:B"]],
            newItemsPlacement: placement()
        )
        let observed = makeObserved(
            items: [aLeftItem, bRightItem],
            sectionByWindowID: [
                aLeftItem.windowID: .visible,
                bRightItem.windowID: .visible,
            ]
        )

        // Suppress unused-warning for a and b; they share fixtures
        // with the items above only for clarity in the scenario.
        _ = a; _ = b

        let move = LayoutReconciler.nextRestoreMove(
            desired: desired,
            observed: observed,
            hasAlwaysHiddenSection: true
        )

        if case .withinSection = move {
            // Expected; the exact uid/destination is pinned by the
            // underlying planner's tests.
        } else {
            XCTFail("expected .withinSection move, got \(String(describing: move))")
        }
    }

    /// All matched → nil.
    func testNothingToReconcileReturnsNil() {
        let inHidden = item(bundleID: "com.example.app", title: "Status", windowID: 700)
        let desired = DesiredLayout.fromSavedSectionOrder(
            ["hidden": ["com.example.app:Status"]],
            newItemsPlacement: placement()
        )
        let observed = makeObserved(
            items: [inHidden],
            sectionByWindowID: [inHidden.windowID: .hidden]
        )

        let move = LayoutReconciler.nextRestoreMove(
            desired: desired,
            observed: observed,
            hasAlwaysHiddenSection: true
        )

        XCTAssertNil(move)
    }

    /// Empty desired and observed → nil.
    func testEmptyDesiredAndObservedReturnsNil() {
        let desired = DesiredLayout(
            sectionOrder: [:],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            newItemsPlacement: placement()
        )
        let observed = makeObserved(items: [], sectionByWindowID: [:])

        let move = LayoutReconciler.nextRestoreMove(
            desired: desired,
            observed: observed,
            hasAlwaysHiddenSection: true
        )

        XCTAssertNil(move)
    }

    // MARK: - unmanagedPlacementPlan

    /// An unmanaged uid with a matching saved position returns .saved.
    func testUnmanagedPlanFavorsSavedPosition() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            ["visible": ["com.known.app:Status"]],
            newItemsPlacement: placement(section: "hidden")
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.known.app:Status"],
            currentUIDs: ["com.known.app:Status"]
        )

        XCTAssertEqual(
            result["com.known.app:Status"],
            .saved(section: .visible, index: 0)
        )
    }

    /// An unmanaged uid with no saved position falls back to
    /// .newItemDefault using the DesiredLayout's NewItemsPlacement.
    func testUnmanagedPlanFallsBackToNewItemDefault() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            [:],
            newItemsPlacement: placement(section: "hidden")
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.new.app:Status"],
            currentUIDs: ["com.new.app:Status"]
        )

        XCTAssertEqual(
            result["com.new.app:Status"],
            .newItemDefault(section: .hidden)
        )
    }

    /// NewItemsPlacement with an anchor present in currentUIDs yields
    /// .newItemAnchored.
    func testUnmanagedPlanUsesNewItemsAnchorWhenPresent() {
        let desired = DesiredLayout.fromSavedSectionOrder(
            [:],
            newItemsPlacement: placement(
                section: "visible",
                anchor: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )

        let result = LayoutReconciler.unmanagedPlacementPlan(
            desired: desired,
            unmanagedUIDs: ["com.new.app:Status"],
            currentUIDs: ["com.new.app:Status", "com.spotlight.app:Anchor"]
        )

        XCTAssertEqual(
            result["com.new.app:Status"],
            .newItemAnchored(
                section: .visible,
                anchorUID: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )
    }
}
