//
//  PlanLeftmostMoveTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

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
@Suite("Plan leftmost move")
struct PlanLeftmostMoveTests {
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
    @Test("The Thaw icon left of the divider takes the Thaw-icon branch")
    func thawIconLeftOfDividerTriggersThawIconBranch() {
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
            #expect(item.windowID == 700)
        } else {
            Issue.record("expected .thawIcon, got \(decision)")
        }
    }

    /// A non-hideable system indicator (camera / mic / screen recording)
    /// left of the divider triggers the system-item recovery branch.
    @Test("A non-hideable system item takes the system-item branch")
    func nonHideableSystemItemTriggersSystemItemBranch() {
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
            #expect(item.windowID == 701)
        } else {
            Issue.record("expected .systemItem, got \(decision)")
        }
    }

    /// A hideable app item that already has an entry in savedSectionOrder
    /// belongs to the restoreItemsToSavedSections path, not the new-item
    /// relocation path. The planner emits .noop(.noNewCandidate).
    @Test("A hideable item with a saved section is deferred")
    func hideableItemWithSavedSectionIsDeferred() {
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

        #expect(decision == .noop(reason: .noNewCandidate))
    }

    /// A hideable item with unresolved sourcePID short-circuits the
    /// candidate-selection cascade. The planner returns .noop with the
    /// unresolvedSourcePID reason.
    @Test("A hideable item with an unresolved source PID is deferred")
    func hideableItemWithUnresolvedSourcePIDIsDeferred() {
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

        #expect(decision == .noop(reason: .unresolvedSourcePID))
    }

    /// A genuinely new hideable item — identifier not in knownItem-
    /// Identifiers, not in any saved section, not already placed in a
    /// hidden tag set — triggers the new-hideable-item relocation.
    @Test("A genuinely new hideable item is relocated")
    func genuinelyNewHideableItemTriggersRelocation() {
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
            #expect(item.windowID == 704)
            #expect(identifierToMark == "com.newapp:Status")
        } else {
            Issue.record("expected .newHideableItem, got \(decision)")
        }
    }

    /// When an item's identifier appears new (not in knownItemIdentifiers)
    /// but its windowID was previously seen, the planner treats this as an
    /// identifier migration (e.g. sourcePID resolution succeeded mid-cycle)
    /// rather than a brand new item. Result: .noop(.noNewCandidate).
    @Test("An identifier migration is not treated as a new item")
    func identifierMigrationIsNotTreatedAsNew() {
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

        #expect(decision == .noop(reason: .noNewCandidate),
                "isNewIdentity && !isNewID should be treated as identifier migration, not new item")
    }

    /// A candidate that is already in the target section produces a
    /// .noop(.alreadyInTarget) decision, avoiding the wasteful move.
    @Test("A candidate already in the target section is a no-op")
    func candidateAlreadyInTargetSectionIsNoop() {
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

        #expect(decision == .noop(reason: .alreadyInTarget))
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
    @Test("A new windowID with an unresolved source PID still short-circuits")
    func newWindowIDWithUnresolvedSourcePIDStillShortCircuits() {
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

        #expect(decision == .noop(reason: .unresolvedSourcePID),
                "nil-sourcePID hideable items must short-circuit even when their windowID is unambiguously new")
    }

    /// With no items left of the divider, the planner emits
    /// .noop(.noLeftmostItems).
    @Test("No items left of the divider yields no leftmost items")
    func emptyLeftmostListReturnsNoLeftmostItems() {
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

        #expect(decision == .noop(reason: .noLeftmostItems))
    }

    // MARK: - Unstable owner titles (#849)

    /// The bundle ID and identifiers here are the ones from the #849 log: the
    /// item the user put in Always Hidden was saved as
    /// `com.shortcutlabs.FlicMac:Item-0`, but the live item arrived tagged
    /// `com.shortcutlabs.FlicMac:com.shortcutlabs.FlicMac` and so matched no
    /// saved entry. Flic owns exactly one status item, so the namespace
    /// identifies it unambiguously and its saved section must still apply.
    @Test("A title change under a sole owner keeps the saved section")
    func titleChangeUnderASoleOwnerKeepsTheSavedSection() {
        let flic = leftmostItem(
            tag: appTag("com.shortcutlabs.FlicMac", "com.shortcutlabs.FlicMac"),
            x: 200,
            windowID: 8368
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [flic],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [flic.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: ["alwaysHidden": ["com.shortcutlabs.FlicMac:Item-0"]],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        #expect(decision == .noop(reason: .noNewCandidate))
    }

    /// The fallback is deliberately limited to owners with a single live item.
    /// With two items under one namespace the saved entry no longer says which
    /// one it meant, so the planner falls back to treating the unmatched item
    /// as new.
    @Test("A title change is not forgiven when the owner has two live items")
    func titleChangeIsNotForgivenWhenTheOwnerHasTwoLiveItems() {
        let renamed = leftmostItem(
            tag: appTag("com.example.app", "Renamed"),
            x: 200,
            windowID: 710
        )
        let sibling = leftmostItem(
            tag: appTag("com.example.app", "Second", 1),
            x: 240,
            windowID: 711
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [renamed, sibling],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [renamed.windowID: .visible, sibling.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: ["alwaysHidden": ["com.example.app:Original"]],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .newHideableItem(item, _) = decision {
            #expect(item.windowID == 710)
        } else {
            Issue.record("expected .newHideableItem, got \(decision)")
        }
    }

    /// Same limit from the other side: an owner with two saved entries has no
    /// single entry the live item can be matched to.
    @Test("A title change is not forgiven when the owner has two saved entries")
    func titleChangeIsNotForgivenWhenTheOwnerHasTwoSavedEntries() {
        let renamed = leftmostItem(
            tag: appTag("com.example.app", "Renamed"),
            x: 200,
            windowID: 712
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [renamed],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [renamed.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: [
                "alwaysHidden": ["com.example.app:Original"],
                "hidden": ["com.example.app:Other"],
            ],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .newHideableItem(item, _) = decision {
            #expect(item.windowID == 712)
        } else {
            Issue.record("expected .newHideableItem, got \(decision)")
        }
    }

    // MARK: - Continuity across a degraded cycle (#849)

    /// The #849 sequence: one enumeration comes back degraded, so the item's
    /// windowID is missing from the immediately preceding cycle, and its
    /// identifier changed as well. Judged on the previous cycle alone the item
    /// looks brand new; the several-cycle history remembers the windowID and
    /// keeps it out of the relocation path.
    @Test("A windowID seen several cycles ago is not new")
    func windowIDSeenSeveralCyclesAgoIsNotNew() {
        let app = leftmostItem(
            tag: appTag("com.example.app", "Renamed"),
            x: 200,
            windowID: 720
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [app.windowID: .visible],
                previousWindowIDs: [],
                recentWindowIDs: [720]
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        #expect(
            decision == .noop(reason: .noNewCandidate),
            "a windowID in the recent history should not be treated as new"
        )
    }

    /// The history must not swallow genuinely new items: a windowID absent from
    /// both the previous cycle and the recent history still relocates.
    @Test("A windowID absent from the recent history is still new")
    func windowIDAbsentFromRecentHistoryIsStillNew() {
        let app = leftmostItem(
            tag: appTag("com.newapp", "Status"),
            x: 200,
            windowID: 721
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [app],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [app.windowID: .visible],
                previousWindowIDs: [999],
                recentWindowIDs: [999, 1000]
            ),
            savedSectionOrder: [:],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .newHideableItem(item, _) = decision {
            #expect(item.windowID == 721)
        } else {
            Issue.record("expected .newHideableItem, got \(decision)")
        }
    }

    /// The Control Center namespace is the shared fallback for every widget
    /// macOS hosts but Thaw cannot yet attribute, so a saved entry under it
    /// says nothing about which item is which. It is excluded from the
    /// namespace fallback even when the counts happen to line up.
    @Test("The Control Center namespace is excluded from the namespace fallback")
    func controlCenterNamespaceIsExcludedFromTheNamespaceFallback() {
        let hosted = leftmostItem(
            tag: appTag("com.apple.controlcenter", "SomeWidget"),
            x: 200,
            windowID: 713
        )

        let decision = LayoutSolver.planLeftmostMove(
            items: [hosted],
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: [hosted.windowID: .visible],
                previousWindowIDs: []
            ),
            savedSectionOrder: ["alwaysHidden": ["com.apple.controlcenter:OtherWidget"]],
            knownItemIdentifiers: [],
            hiddenTags: [],
            alwaysHiddenTags: [],
            effectiveNewItemsSection: .hidden
        )

        if case let .newHideableItem(item, _) = decision {
            #expect(item.windowID == 713)
        } else {
            Issue.record("expected .newHideableItem, got \(decision)")
        }
    }

    // MARK: - Thaw icon, standalone

    /// planThawIconMove is what the startup-settling path calls, before the
    /// other items' namespace tags are trustworthy. It must agree with the
    /// Thaw-icon branch of the full planner.
    @Test("planThawIconMove finds the Thaw icon left of the divider")
    func planThawIconMoveFindsIconLeftOfDivider() {
        let thaw = leftmostItem(tag: .visibleControlItem, x: 100, windowID: 700)

        let icon = LayoutSolver.planThawIconMove(items: [thaw], hiddenBounds: hiddenBounds)

        #expect(icon?.windowID == 700)
    }

    /// Once the icon sits right of the divider it is on screen, so repeated
    /// settling polls must not keep moving it.
    @Test("planThawIconMove returns nil when the Thaw icon is already placed")
    func planThawIconMoveIgnoresIconRightOfDivider() {
        let thaw = leftmostItem(tag: .visibleControlItem, x: 500, windowID: 700)

        let icon = LayoutSolver.planThawIconMove(items: [thaw], hiddenBounds: hiddenBounds)

        #expect(icon == nil)
    }

    /// The settling path must act on the Thaw icon only. Third-party items
    /// left of the divider are the ones whose tags aren't settled yet, and
    /// deferring them is the whole point of the settling guard.
    @Test("planThawIconMove ignores non-Thaw items left of the divider")
    func planThawIconMoveIgnoresOtherLeftmostItems() {
        let other = leftmostItem(tag: appTag("com.example.app", "Item"), x: 100, windowID: 710)
        let unresolved = leftmostItem(
            tag: .appItem(bundleID: "com.apple.controlcenter", title: "Item-0"),
            x: 150,
            windowID: 711,
            sourcePID: nil
        )

        let icon = LayoutSolver.planThawIconMove(
            items: [other, unresolved],
            hiddenBounds: hiddenBounds
        )

        #expect(icon == nil)
    }
}
