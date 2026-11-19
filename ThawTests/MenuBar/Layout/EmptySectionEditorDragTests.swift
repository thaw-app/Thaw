//
//  EmptySectionEditorDragTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers LayoutBarPaddingView.shouldRevealSectionForEditorDrag.
///
/// With Hidden empty, both dividers park at the same offscreen coordinate, so a
/// drag into Hidden resolves to .leftOfItem(H_ctrl), which the #923 guard
/// refuses. Its "open the section and retry" advice deadlocks on an empty
/// section, so the empty section is revealed instead. The rule stays narrow:
/// populated sections anchor on items, a showing section's divider is onscreen,
/// and non-divider tags never get here.
@Suite("Empty-section editor drag reveal (#988)")
struct EmptySectionEditorDragTests {
    private let screen = CGRect(x: 0, y: 0, width: 1496, height: 967)
    private let onDisplay = CGRect(x: 632, y: 0, width: 3, height: 29)

    /// Only an empty Always Hidden drop needs to ask the window server for visibility.
    @Test("Initial editor drop checks visibility only for an empty Always Hidden section")
    func onlyEmptyAlwaysHiddenNeedsLiveVisibility() {
        var queries = 0
        for (tag, empty, expected) in [
            (MenuBarItemTag.hiddenControlItem, true, true),
            (.alwaysHiddenControlItem, false, true),
            (.alwaysHiddenControlItem, true, false),
        ] {
            let reachable = LayoutBarPaddingView.isInitialEditorDropDividerReachable(
                tag: tag, bounds: onDisplay, alwaysHiddenIsEmpty: empty, screenFrames: [screen]
            ) {
                queries += 1
                return false
            }
            #expect(reachable == expected)
        }
        #expect(queries == 1)
    }

    /// A reachable divider keeps its target and never requests a temporary reveal.
    @MainActor
    @Test("An already visible divider needs no reveal or settle delay")
    func reachableDividerKeepsOriginalDestination() async throws {
        let item = MenuBarItem.fixture(tag: .alwaysHiddenControlItem, windowID: 1)
        let identifier = UUID()
        let result = try #require(await LayoutBarPaddingView.resolveEditorDropDivider(
            destination: .rightOfItem(item), revealID: identifier, screenFrames: [screen], initialBounds: onDisplay,
            section: { _ in
                Issue.record("A visible divider must not look up sections to reveal")
                return nil
            },
            itemCount: { _ in 0 }, liveVisibility: { $0 == item.windowID }
        ))
        #expect(result.destination.targetItem.windowID == item.windowID)
        #expect(result.sections.isEmpty)
        await LayoutBarPaddingView.finishEditorDropReveal(result.sections, revealID: identifier) {
            Issue.record("No menu bar change means no settle delay")
        }
    }

    /// The editor retargets to the fresh visible divider and keeps both sections open for the move.
    @MainActor
    @Test("Reveal waits for a fresh visible divider without changing the drop side", arguments: [true, false])
    func revealReturnsFreshDivider(dropOnLeft: Bool) async {
        let sections = [MenuBarSection(name: .hidden), MenuBarSection(name: .alwaysHidden)]
        let identifier = UUID()
        let stale = MenuBarItem.fixture(tag: .alwaysHiddenControlItem, windowID: 1, isOnScreen: false)
        let fresh = MenuBarItem.fixture(tag: .alwaysHiddenControlItem, windowID: 2, isOnScreen: true)
        let destination: MenuBarItemManager.MoveDestination = dropOnLeft ? .leftOfItem(stale) : .rightOfItem(stale)
        var snapshots = ArraySlice([[stale], [fresh]])
        let result = await LayoutBarPaddingView.resolveEditorDropDivider(
            destination: destination, revealID: identifier, screenFrames: [screen], initialBounds: onDisplay,
            section: { name in sections.first { $0.name == name } },
            itemCount: { _ in 0 }, isEnabled: { _ in true },
            wait: {}, items: { snapshots.popFirst() ?? [] },
            bounds: { _ in onDisplay }, liveVisibility: { _ in false }
        )
        #expect(result?.destination.targetItem.windowID == fresh.windowID)
        switch result?.destination {
        case .leftOfItem: #expect(dropOnLeft)
        case .rightOfItem: #expect(!dropOnLeft)
        case nil: Issue.record("Expected a reachable destination")
        }
        #expect(result?.sections.map(\.name) == [.hidden, .alwaysHidden])
        #expect(snapshots.isEmpty)
        #expect(sections.allSatisfy { $0.controlItem.showsTemporaryDivider })
        await LayoutBarPaddingView.finishEditorDropReveal(sections, revealID: identifier) {
            #expect(sections.allSatisfy { !$0.controlItem.showsTemporaryDivider })
        }
        #expect(sections.allSatisfy { !$0.controlItem.showsTemporaryDivider })
    }

    /// Timeout releases the reveal even when WindowServer returns no matching divider.
    @MainActor
    @Test("A missing divider times out and releases the reveal")
    func missingDividerUnwindsReveal() async {
        let section = MenuBarSection(name: .hidden)
        let item = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 1)
        var polls = 0
        let result = await LayoutBarPaddingView.resolveEditorDropDivider(
            destination: .leftOfItem(item), revealID: UUID(), screenFrames: [screen],
            section: { _ in section }, itemCount: { _ in 0 }, isEnabled: { _ in true }, wait: {},
            items: {
                polls += 1
                return []
            },
            bounds: { _ in nil }
        )
        #expect(result == nil)
        #expect(polls == 40)
        #expect(!section.controlItem.showsTemporaryDivider)
    }

    /// A window can disappear between enumeration and the live bounds query.
    @MainActor
    @Test("A snapshot whose window has disappeared cannot become the drop target")
    func disappearedWindowUnwindsReveal() async {
        let sections = [MenuBarSection(name: .hidden), MenuBarSection(name: .alwaysHidden)]
        let item = MenuBarItem.fixture(tag: .alwaysHiddenControlItem, windowID: .max)
        var snapshots = ArraySlice([[item]])
        let result = await LayoutBarPaddingView.resolveEditorDropDivider(
            destination: .leftOfItem(item), revealID: UUID(), screenFrames: [screen], initialBounds: onDisplay,
            section: { name in sections.first { $0.name == name } },
            itemCount: { _ in 0 }, isEnabled: { _ in true },
            items: { snapshots.popFirst() ?? [] }
        )
        #expect(result == nil)
        #expect(snapshots.isEmpty)
        #expect(sections.allSatisfy { !$0.controlItem.showsTemporaryDivider })
    }

    /// Cancellation releases only the cancelled drag's claim on the divider.
    @MainActor
    @Test("Cancelling a reveal preserves the divider for another drag")
    func cancelledRevealReleasesOnlyItsClaim() async {
        let section = MenuBarSection(name: .hidden)
        let item = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 1)
        let otherDrag = UUID()
        let task = Task {
            await LayoutBarPaddingView.resolveEditorDropDivider(
                destination: .leftOfItem(item), revealID: UUID(), screenFrames: [screen],
                section: { _ in section }, itemCount: { _ in 0 }, isEnabled: { _ in true },
                wait: {
                    section.controlItem.beginEditorDragReveal(otherDrag)
                    withUnsafeCurrentTask { $0?.cancel() }
                },
                items: {
                    Issue.record("A cancelled reveal must not query the window server")
                    return []
                },
                bounds: { _ in nil }
            )
        }
        let result = await task.value
        #expect(result == nil)
        #expect(section.controlItem.showsTemporaryDivider)
        await LayoutBarPaddingView.finishEditorDropReveal([section], revealID: otherDrag)
        #expect(!section.controlItem.showsTemporaryDivider)
    }

    /// Invalid or incomplete section layouts must not touch the menu bar.
    @MainActor
    @Test("A reveal refuses an ineligible or missing section before polling")
    func revealSkipsUnavailableSections() async {
        let section = MenuBarSection(name: .alwaysHidden)
        let cases: [(tag: MenuBarItemTag, hasSection: Bool, itemCount: Int)] = [
            (.visibleControlItem, true, 0),
            (.alwaysHiddenControlItem, false, 0),
            (.alwaysHiddenControlItem, true, 1),
            (.alwaysHiddenControlItem, true, 0),
        ]
        for testCase in cases {
            let item = MenuBarItem.fixture(tag: testCase.tag, windowID: 1)
            let result = await LayoutBarPaddingView.resolveEditorDropDivider(
                destination: .leftOfItem(item), revealID: UUID(), screenFrames: [screen],
                section: { testCase.hasSection && $0 == .alwaysHidden ? section : nil },
                itemCount: { _ in testCase.itemCount }, isEnabled: { _ in true },
                wait: { Issue.record("Invalid drop must not start polling") }
            )
            #expect(result == nil)
            #expect(!section.controlItem.showsTemporaryDivider)
        }
    }

    /// The window server can report on-display coordinates for a concealed divider.
    @Test("A geometrically on-display divider must be visible for an empty Always Hidden drop")
    func emptyAlwaysHiddenDividerRequiresVisibility() {
        let display = CGRect(x: 0, y: 0, width: 1496, height: 967)
        let divider = CGRect(x: 632, y: 0, width: 1, height: 29)

        for isOnScreen in [false, true] {
            #expect(
                LayoutBarPaddingView.isEditorDropDividerReachable(
                    bounds: divider,
                    isOnScreen: isOnScreen,
                    requiresVisibility: true,
                    screenFrames: [display]
                ) == isOnScreen
            )
        }
    }

    /// Ordinary dividers still use the existing leading-edge geometry check.
    @Test("Ordinary dividers retain their geometry-only reachability check")
    func ordinaryDividersKeepGeometryCheck() {
        let display = CGRect(x: 0, y: 0, width: 1496, height: 967)
        let onDisplay = CGRect(x: 1039, y: 0, width: 1, height: 29)
        let parked = CGRect(x: -4382, y: 0, width: 1, height: 29)

        #expect(LayoutBarPaddingView.isEditorDropDividerReachable(
            bounds: onDisplay,
            isOnScreen: false,
            requiresVisibility: false,
            screenFrames: [display]
        ))
        #expect(!LayoutBarPaddingView.isEditorDropDividerReachable(
            bounds: parked,
            isOnScreen: true,
            requiresVisibility: true,
            screenFrames: [display]
        ))
        #expect(!LayoutBarPaddingView.isEditorDropDividerReachable(
            bounds: nil,
            isOnScreen: true,
            requiresVisibility: false,
            screenFrames: [display]
        ))
    }

    @Test("An empty concealed section reveals — the #988 deadlock")
    func emptyConcealedSectionReveals() {
        #expect(
            LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .hiddenControlItem,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 0
            )
        )
        #expect(
            LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .alwaysHiddenControlItem,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 0
            )
        )
    }

    @Test("A populated section does not reveal")
    func populatedSectionDoesNotReveal() {
        // Items in the section anchor the drop; the clamp-and-retry path owns this case.
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .hiddenControlItem,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 1
            )
        )
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .hiddenControlItem,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 8
            )
        )
    }

    @Test("A disabled section never reveals")
    func disabledSectionDoesNotReveal() {
        // A divider not in the menu bar has nothing to bring onscreen.
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .hiddenControlItem,
                isSectionConcealed: true,
                isEnabled: false,
                sectionItemCount: 0
            )
        )
    }

    @Test("A showing section does not reveal")
    func showingSectionDoesNotReveal() {
        // Not concealed means the divider is onscreen, so the reachability gate never fires.
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .hiddenControlItem,
                isSectionConcealed: false,
                isEnabled: true,
                sectionItemCount: 0
            )
        )
    }

    @Test("A non-divider tag never reveals")
    func nonDividerTagDoesNotReveal() {
        // The chevron is never a parked section boundary, and regular items have their own move paths.
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .visibleControlItem,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 0
            )
        )
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .audioVideoModule,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 0
            )
        )
        #expect(
            !LayoutBarPaddingView.shouldRevealSectionForEditorDrag(
                dividerTag: .clock,
                isSectionConcealed: true,
                isEnabled: true,
                sectionItemCount: 0
            )
        )
    }

    @Test("An always-hidden destination reveals the hidden section with it (#1010)")
    func alwaysHiddenDestinationRevealsLeadingSections() {
        // The always-hidden divider parks left of the hidden section's content, so
        // revealing always-hidden alone leaves it offscreen and the reveal times out
        // into the #923 refusal (#1010). Hidden must expand with it.
        #expect(
            LayoutBarPaddingView.sectionsToRevealForEditorDrag(forDividerTag: .alwaysHiddenControlItem)
                == [.hidden, .alwaysHidden]
        )
        // Nothing is parked ahead of a hidden destination; non-divider tags reveal nothing.
        #expect(
            LayoutBarPaddingView.sectionsToRevealForEditorDrag(forDividerTag: .hiddenControlItem)
                == [.hidden]
        )
        #expect(LayoutBarPaddingView.sectionsToRevealForEditorDrag(forDividerTag: .visibleControlItem).isEmpty)
        #expect(LayoutBarPaddingView.sectionsToRevealForEditorDrag(forDividerTag: .clock).isEmpty)
    }
}
