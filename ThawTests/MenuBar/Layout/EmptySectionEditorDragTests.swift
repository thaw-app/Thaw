//
//  EmptySectionEditorDragTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `LayoutBarPaddingView.shouldRevealSectionForEditorDrag`.
///
/// With Hidden empty, both dividers park at the same offscreen coordinate, so a
/// drag into Hidden resolves to `.leftOfItem(H_ctrl)`, which the #923 guard
/// refuses. Its "open the section and retry" advice deadlocks on an empty
/// section, so the empty section is revealed instead. The rule stays narrow:
/// populated sections anchor on items, a showing section's divider is onscreen,
/// and non-divider tags never get here.
@Suite("Empty-section editor drag reveal (#988)")
struct EmptySectionEditorDragTests {
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
