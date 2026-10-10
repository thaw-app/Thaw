//
//  PlanLeftmostMoveTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// LayoutSolver.planLeftmostMove, the cascade behind relocateNewLeftmostItems:
/// Thaw icon, non-hideable system item, new hideable item, then noop.
///
/// Hidden divider at x=400, width 10; items with maxX <= 400 are leftmost.
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

    /// Camera, mic, and screen-recording indicators are non-hideable.
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

    /// An item with a saved section belongs to restoreItemsToSavedSections, not this path.
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

    /// Not a known identifier, not in any saved section, and not already in a hidden tag set.
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

    /// A new identifier on a known windowID is a migration (such as sourcePID
    /// resolving mid-cycle), not a new item.
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
                // Already in .hidden, which is the new-items section.
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

    /// A new arrival whose sourcePID neither the AX pass nor the marker-pair
    /// fallback resolved stays at macOS's default spot rather than moving an
    /// unstable identifier. Loosening this (such as tracking by windowID) must
    /// change this assertion deliberately.
    @Test("A new windowID with an unresolved source PID still short-circuits")
    func newWindowIDWithUnresolvedSourcePIDStillShortCircuits() {
        let newApp = leftmostItem(
            // On macOS 26 a failed sourcePID resolution yields com.apple.controlcenter:Item-0:N.
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
                // The real bundle ID is saved, but the placeholder won't match it.
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

    @Test("No items left of the divider yields no leftmost items")
    func emptyLeftmostListReturnsNoLeftmostItems() {
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

    /// The #849 log: saved as `com.shortcutlabs.FlicMac:Item-0`, live as
    /// `com.shortcutlabs.FlicMac:com.shortcutlabs.FlicMac`. Flic owns one status
    /// item, so the namespace identifies it and its saved section still applies.
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

    /// With two live items under one namespace the saved entry is ambiguous, so the item is new.
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

    /// With two saved entries under one owner, there is no single match.
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

    /// A degraded enumeration drops the windowID from the previous cycle while the
    /// identifier also changes. The several-cycle history still remembers it (#849).
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

    /// The history must not swallow genuinely new items.
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

    /// Control Center is the shared fallback namespace for unattributed widgets,
    /// so a saved entry under it identifies nothing, whatever the counts.
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

    /// The startup-settling path calls this before other tags are trustworthy; it
    /// must agree with the full planner's Thaw-icon branch.
    @Test("planThawIconMove finds the Thaw icon left of the divider")
    func planThawIconMoveFindsIconLeftOfDivider() {
        let thaw = leftmostItem(tag: .visibleControlItem, x: 100, windowID: 700)

        let icon = LayoutSolver.planThawIconMove(items: [thaw], hiddenBounds: hiddenBounds)

        #expect(icon?.windowID == 700)
    }

    /// Once placed right of the divider, settling polls must not keep moving it.
    @Test("planThawIconMove returns nil when the Thaw icon is already placed")
    func planThawIconMoveIgnoresIconRightOfDivider() {
        let thaw = leftmostItem(tag: .visibleControlItem, x: 500, windowID: 700)

        let icon = LayoutSolver.planThawIconMove(items: [thaw], hiddenBounds: hiddenBounds)

        #expect(icon == nil)
    }

    /// Third-party items left of the divider have unsettled tags; deferring them is the point.
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
