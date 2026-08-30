//
//  EmptySectionEditorDragTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `LayoutBarPaddingView.shouldRevealSectionForEditorDrag`, the
/// decision behind the #988 fix.
///
/// #988: with an empty Hidden section, both dividers park offscreen at the
/// same coordinate (the reporter's log shows `hidden.minX=-3861.0` and
/// `alwaysHidden.maxX=-3861.0`), so a drag into Hidden resolves to
/// `.leftOfItem(H_ctrl)` — a parked divider the #923 guard must refuse. The
/// refusal's "open the section and try dragging the item again" advice
/// deadlocks there: an empty section has nothing to open, so every retry
/// hits the same refusal. The fix reveals the empty section instead of
/// refusing, which this predicate gates. It must stay narrow: populated
/// sections anchor drops on their items, a showing section has its divider
/// onscreen, and non-divider tags never route through the decision.
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
        // With items in the section the drop anchors on those items and the
        // clamp-and-retry move path owns the case.
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
        // isEnabled is part of the reveal predicate: a section whose divider
        // is not added to the menu bar has nothing to bring onscreen.
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
        // Concealed == false means the divider is onscreen; the reachability
        // gate never fires.
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
        // The visible chevron is a control item but never a parked section
        // boundary, and regular items have their own move paths.
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
}
