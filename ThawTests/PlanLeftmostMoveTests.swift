//
//  PlanLeftmostMoveTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.planLeftmostMove.
///
/// Pins down the four-branch cascade used by relocateNewLeftmostItems:
/// (1) Thaw icon, (2) non-hideable system item, (3) new hideable item,
/// (4) noop. Each scenario layouts the inputs at the planner boundary so
/// no Bridging or instance state is involved.
///
/// Coordinate convention: hidden divider at x=400, width=10. Items with
/// maxX <= 400 are "leftmost" (left of divider). Items further right are
/// either at the divider or beyond.
final class PlanLeftmostMoveTests: XCTestCase {
    // MARK: - Helpers

    private let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)

    private func leftmostItem(
        tag: MenuBarItemTag,
        x: CGFloat,
        windowID: CGWindowID,
        sourcePID: pid_t? = 1234
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: tag,
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22),
            sourcePID: sourcePID
        )
    }

    private func appTag(_ bundleID: String, _ title: String, _ instanceIndex: Int = 0) -> MenuBarItemTag {
        .appItem(bundleID: bundleID, title: title, instanceIndex: instanceIndex)
    }

    // MARK: - Scenarios

    /// The Thaw visible-control icon left of the divider triggers the
    /// Thaw-icon recovery branch.
    func testThawIconLeftOfDividerTriggersThawIconBranch() {
        let thaw = leftmostItem(
            tag: .visibleControlItem,
            x: 100,
            windowID: 700
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [thaw],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [thaw.windowID: .hidden],
                previousWindowIDs: []
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .thawIcon(item) = decision {
            XCTAssertEqual(item.windowID, 700)
        } else {
            XCTFail("expected .thawIcon, got \(decision)")
        }
    }

    /// A non-hideable system indicator (camera / mic / screen recording)
    /// left of the divider triggers the system-item recovery branch.
    func testNonHideableSystemItemTriggersSystemItemBranch() {
        let screenCap = leftmostItem(
            tag: .screenCaptureUI,
            x: 150,
            windowID: 701
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [screenCap],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [screenCap.windowID: .hidden],
                previousWindowIDs: []
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .systemItem(item) = decision {
            XCTAssertEqual(item.windowID, 701)
        } else {
            XCTFail("expected .systemItem, got \(decision)")
        }
    }

    /// A hideable app item that already has an entry in savedSectionOrder
    /// belongs to the restoreItemsToSavedSections path, not the new-item
    /// relocation path. The planner emits .noop(.noNewCandidate).
    func testHideableItemWithSavedSectionIsDeferred() {
        let app = leftmostItem(
            tag: appTag("com.example.app", "Status"),
            x: 200,
            windowID: 702
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [app.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: ["hidden": ["com.example.app:Status"]],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        XCTAssertEqual(decision, .noop(reason: .noNewCandidate))
    }

    /// A hideable item with unresolved sourcePID short-circuits the
    /// candidate-selection cascade. The planner returns .noop with the
    /// unresolvedSourcePID reason.
    func testHideableItemWithUnresolvedSourcePIDIsDeferred() {
        let app = leftmostItem(
            tag: appTag("com.example.app", "Status"),
            x: 200,
            windowID: 703,
            sourcePID: nil
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [app.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        XCTAssertEqual(decision, .noop(reason: .unresolvedSourcePID))
    }

    /// A genuinely new hideable item — identifier not in knownItem-
    /// Identifiers, not in any saved section, not already placed in a
    /// hidden tag set — triggers the new-hideable-item relocation.
    func testGenuinelyNewHideableItemTriggersRelocation() {
        let app = leftmostItem(
            tag: appTag("com.newapp", "Status"),
            x: 200,
            windowID: 704
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [app.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .newHideableItem(item, identifierToMark) = decision {
            XCTAssertEqual(item.windowID, 704)
            XCTAssertEqual(identifierToMark, "com.newapp:Status")
        } else {
            XCTFail("expected .newHideableItem, got \(decision)")
        }
    }

    /// When an item's identifier appears new (not in knownItemIdentifiers)
    /// but its windowID was previously seen, the planner treats this as an
    /// identifier migration (e.g. sourcePID resolution succeeded mid-cycle)
    /// rather than a brand new item. Result: .noop(.noNewCandidate).
    func testIdentifierMigrationIsNotTreatedAsNew() {
        let app = leftmostItem(
            tag: appTag("com.example.app", "Status"),
            x: 200,
            windowID: 705
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [app.windowID: .visible],
                previousWindowIDs: [705] // windowID was seen before
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [], // but identifier is "new"
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        XCTAssertEqual(decision, .noop(reason: .noNewCandidate),
                       "isNewIdentity && !isNewID should be treated as identifier migration, not new item")
    }

    /// A candidate that is already in the target section produces a
    /// .noop(.alreadyInTarget) decision, avoiding the wasteful move.
    func testCandidateAlreadyInTargetSectionIsNoop() {
        let app = leftmostItem(
            tag: appTag("com.newapp", "Status"),
            x: 200,
            windowID: 706
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                // sectionByWindowID claims the item is already in .hidden,
                // which is also the effectiveNewItemsSection, so moving
                // would be a no-op.
                sectionByWindowID: [app.windowID: .hidden],
                previousWindowIDs: []
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        XCTAssertEqual(decision, .noop(reason: .alreadyInTarget))
    }

    /// A brand-new mid-session app arrival (windowID not in
    /// previousWindowIDs) whose sourcePID could not be resolved by
    /// the spatial AX pass nor by the marker-pair fallback still
    /// short-circuits with .unresolvedSourcePID. The current
    /// behavior leaves the icon at macOS's default leftmost
    /// placement rather than relocating an item whose identifier is
    /// unstable. Any future loosening (e.g. tracking by windowID
    /// instead of identifier) must replace this assertion
    /// deliberately so the regression risk is explicit.
    func testNewWindowIDWithUnresolvedSourcePIDStillShortCircuits() {
        let newApp = leftmostItem(
            // Identifier collapses to com.apple.controlcenter:Item-0:N
            // when sourcePID resolution fails on macOS 26; the test
            // models the placeholder namespace the orchestrator
            // actually sees in that case.
            tag: appTag("com.apple.controlcenter", "Item-0", 1),
            x: 100,
            windowID: 999, // fresh windowID
            sourcePID: nil
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [newApp],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [newApp.windowID: .visible],
                previousWindowIDs: [101, 102, 103] // windowID 999 is new
            ),
            savedSectionOrder: [
                // The widget's real bundle ID is saved, but the live
                // item's placeholder identifier won't match.
                "hidden": ["com.wireguard.macos:Item-0"],
            ],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        XCTAssertEqual(decision, .noop(reason: .unresolvedSourcePID),
                       "nil-sourcePID hideable items must short-circuit even when their windowID is unambiguously new")
    }

    /// With no items left of the divider, the planner emits
    /// .noop(.noLeftmostItems).
    func testEmptyLeftmostListReturnsNoLeftmostItems() {
        // All items sit to the right of the hidden divider (minX >= 500).
        let visibleApp = MenuBarItem.fixture(
            tag: appTag("com.example.app", "Status"),
            windowID: 707,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [visibleApp],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [visibleApp.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        XCTAssertEqual(decision, .noop(reason: .noLeftmostItems))
    }
}
