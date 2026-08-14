//
//  LayoutReconcilerUnmanagedPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``LayoutReconciler/applyUnmanagedPlacementsToDesired(placements:unmanagedUIDs:desiredFiltered:sectionMap:savedSectionOrder:controlUIDs:)``,
/// the three-pass insertion that splices unmanaged items into the abstract
/// desired-layout sequence during a profile apply.
///
/// `LayoutReconcilerTests` covers the reconciler's destination-resolution
/// surface. This suite covers the sequence surgery, which is where the
/// subtle bugs live: the function mutates a positional array while
/// simultaneously deriving section bounds *from* that same array, so every
/// insertion shifts the boundaries the next insertion depends on. Getting
/// this wrong silently scrambles the user's menu bar.
///
/// The function is pure — dictionaries and arrays in, a tuple out — so the
/// suite drives it directly with no fixtures or system state.
///
/// Sequence convention throughout: index 0 is leftmost, and the array runs
/// chevron → visible items → hidden control → hidden items → always-hidden
/// control → always-hidden items.
@Suite("Layout reconciler unmanaged placement")
struct LayoutReconcilerUnmanagedPlacementTests {
    // MARK: - Fixtures

    private static let chevron = "control:visible"
    private static let hiddenControl = "control:hidden"
    private static let alwaysHiddenControl = "control:alwaysHidden"

    /// Full control set: chevron and always-hidden section both enabled.
    private static let allControls = ControlUIDs(
        visible: chevron,
        hidden: hiddenControl,
        alwaysHidden: alwaysHiddenControl
    )

    /// Convenience wrapper so each test reads as inputs → outputs rather
    /// than a wall of argument labels.
    private func apply(
        placements: [String: LayoutSolver.UnmanagedPlacement],
        unmanagedUIDs: [String],
        desiredFiltered: [String],
        sectionMap: [String: String] = [:],
        savedSectionOrder: [String: [String]] = [:],
        controlUIDs: ControlUIDs = Self.allControls
    ) -> (desiredFiltered: [String], sectionMap: [String: String]) {
        LayoutReconciler.applyUnmanagedPlacementsToDesired(
            placements: placements,
            unmanagedUIDs: unmanagedUIDs,
            desiredFiltered: desiredFiltered,
            sectionMap: sectionMap,
            savedSectionOrder: savedSectionOrder,
            controlUIDs: controlUIDs
        )
    }

    // MARK: - Degenerate inputs

    @Test("Empty inputs produce an empty sequence and an empty section map")
    func emptyInputsAreReturnedUnchanged() {
        let result = apply(placements: [:], unmanagedUIDs: [], desiredFiltered: [])

        #expect(result.desiredFiltered.isEmpty)
        #expect(result.sectionMap.isEmpty)
    }

    @Test("Unmanaged uids with no placement entry are dropped rather than appended")
    func unmanagedUIDsWithoutPlacementsAreIgnored() {
        let sequence = [Self.chevron, "app:visible", Self.hiddenControl]

        let result = apply(
            placements: [:],
            unmanagedUIDs: ["app:unplaced", "app:alsoUnplaced"],
            desiredFiltered: sequence
        )

        #expect(result.desiredFiltered == sequence)
        #expect(result.sectionMap.isEmpty)
    }

    @Test("An existing section map is carried through and extended, not replaced")
    func existingSectionMapEntriesArePreserved() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .hidden)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, Self.hiddenControl],
            sectionMap: ["app:preexisting": "visible"]
        )

        #expect(result.sectionMap["app:preexisting"] == "visible")
        #expect(result.sectionMap["app:new"] == "hidden")
    }

    // MARK: - Pass 3: default placements

    @Test("A visible default placement lands at the end of the visible section, left of the hidden control")
    func visibleDefaultLandsBeforeHiddenControl() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .visible)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:visible", Self.hiddenControl, "app:hidden"]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:visible", "app:new", Self.hiddenControl, "app:hidden",
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("A hidden default placement lands left of the always-hidden control")
    func hiddenDefaultLandsBeforeAlwaysHiddenControl() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .hidden)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [
                Self.chevron, Self.hiddenControl, "app:hidden",
                Self.alwaysHiddenControl, "app:alwaysHidden",
            ]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, Self.hiddenControl, "app:hidden", "app:new",
            Self.alwaysHiddenControl, "app:alwaysHidden",
        ])
        #expect(result.sectionMap["app:new"] == "hidden")
    }

    @Test("An always-hidden default placement is appended to the very end of the sequence")
    func alwaysHiddenDefaultIsAppended() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .alwaysHidden)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [
                Self.chevron, Self.hiddenControl, Self.alwaysHiddenControl, "app:alwaysHidden",
            ]
        )

        #expect(result.desiredFiltered.last == "app:new")
        #expect(result.sectionMap["app:new"] == "alwaysHidden")
    }

    @Test("A hidden default placement is appended when the always-hidden section is disabled")
    func hiddenDefaultIsAppendedWithoutAlwaysHiddenControl() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .hidden)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, Self.hiddenControl, "app:hidden"],
            controlUIDs: ControlUIDs(visible: Self.chevron, hidden: Self.hiddenControl, alwaysHidden: nil)
        )

        #expect(result.desiredFiltered == [
            Self.chevron, Self.hiddenControl, "app:hidden", "app:new",
        ])
    }

    @Test("A hidden placement falls to the end of the sequence when the hidden control is missing from it")
    func hiddenDefaultFallsToSequenceEndWhenControlAbsent() {
        // The hidden control uid is declared but never appears in the
        // sequence, so no boundary can be located.
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .hidden)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:visible"],
            controlUIDs: ControlUIDs(visible: Self.chevron, hidden: Self.hiddenControl, alwaysHidden: nil)
        )

        #expect(result.desiredFiltered == [Self.chevron, "app:visible", "app:new"])
    }

    @Test("Several default placements in one section keep their unmanagedUIDs order")
    func defaultPlacementsPreserveUnmanagedOrder() {
        let result = apply(
            placements: [
                "app:first": .newItemDefault(section: .visible),
                "app:second": .newItemDefault(section: .visible),
                "app:third": .newItemDefault(section: .visible),
            ],
            unmanagedUIDs: ["app:first", "app:second", "app:third"],
            desiredFiltered: [Self.chevron, Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:first", "app:second", "app:third", Self.hiddenControl,
        ])
    }

    // MARK: - Pass 2: anchored placements

    @Test("An anchored placement with the leftOfAnchor relation takes the anchor's index")
    func anchoredLeftOfAnchorTakesAnchorIndex() {
        let result = apply(
            placements: [
                "app:new": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .leftOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:left", "app:anchor", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:left", "app:new", "app:anchor", Self.hiddenControl,
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("An anchored placement with the rightOfAnchor relation lands just after the anchor")
    func anchoredRightOfAnchorLandsAfterAnchor() {
        let result = apply(
            placements: [
                "app:new": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .rightOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:anchor", "app:right", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:anchor", "app:new", "app:right", Self.hiddenControl,
        ])
    }

    // MARK: - Pass 2: multiple anchored placements sharing one anchor

    //
    // `LayoutSolver.planUnmanagedPlacement` gives every unmanaged item that
    // lacks a saved position the *same* `.newItemAnchored` placement — the
    // user's configured NewItemsPlacement anchor — so several items sharing
    // one anchor is the common case, not an edge case. These tests pin the
    // contract that the group keeps its unmanagedUIDs relative order, which
    // mirrors the order-preservation guarantee Pass 3 states explicitly.

    @Test("Several rightOfAnchor placements sharing one anchor keep their unmanagedUIDs order")
    func rightOfAnchorPlacementsPreserveUnmanagedOrder() {
        // Inserting after the anchor does not shift it, so a naive rightOf
        // pass re-derives the same `anchorIdx + 1` slot on every iteration
        // and reverses the group ([anchor, second, first] instead of
        // [anchor, first, second]). The pass must advance past the items
        // already placed right of the anchor.
        let result = apply(
            placements: [
                "app:first": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .rightOfAnchor
                ),
                "app:second": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .rightOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:first", "app:second"],
            desiredFiltered: [Self.chevron, "app:anchor", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:anchor", "app:first", "app:second", Self.hiddenControl,
        ])
        #expect(result.sectionMap["app:first"] == "visible")
        #expect(result.sectionMap["app:second"] == "visible")
    }

    @Test("Three rightOfAnchor placements sharing one anchor keep their order")
    func rightOfAnchorPreservesOrderForThreeItems() {
        // The offset must scale with the group size, not just the pair case.
        let result = apply(
            placements: [
                "app:a": .newItemAnchored(section: .visible, anchorUID: "app:anchor", relation: .rightOfAnchor),
                "app:b": .newItemAnchored(section: .visible, anchorUID: "app:anchor", relation: .rightOfAnchor),
                "app:c": .newItemAnchored(section: .visible, anchorUID: "app:anchor", relation: .rightOfAnchor),
            ],
            unmanagedUIDs: ["app:a", "app:b", "app:c"],
            desiredFiltered: [Self.chevron, "app:anchor", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:anchor", "app:a", "app:b", "app:c", Self.hiddenControl,
        ])
    }

    @Test("Several leftOfAnchor placements sharing one anchor keep their unmanagedUIDs order")
    func leftOfAnchorPlacementsPreserveUnmanagedOrder() {
        // Mirror of the rightOf case. leftOf already preserves order
        // because inserting before the anchor shifts it right, advancing
        // the resolved anchor index. Pinned here so the rightOf fix cannot
        // silently regress the leftOf path.
        let result = apply(
            placements: [
                "app:first": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .leftOfAnchor
                ),
                "app:second": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .leftOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:first", "app:second"],
            desiredFiltered: [Self.chevron, "app:anchor", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:first", "app:second", "app:anchor", Self.hiddenControl,
        ])
    }

    @Test("An anchored placement with the sectionDefault relation ignores its anchor and lands at the section end")
    func anchoredSectionDefaultRelationLandsAtSectionEnd() {
        // .sectionDefault means "no anchor preference", so the anchor uid
        // riding along on the placement is not a positioning request. The
        // item takes the same section-default position it would take if
        // the anchor had vanished — here that is after "app:tail", not
        // immediately right of the anchor.
        let result = apply(
            placements: [
                "app:new": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:anchor",
                    relation: .sectionDefault
                ),
            ],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:anchor", "app:tail", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:anchor", "app:tail", "app:new", Self.hiddenControl,
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("An anchored placement whose anchor is absent falls back to the section end")
    func anchoredPlacementFallsBackWhenAnchorMissing() {
        let result = apply(
            placements: [
                "app:new": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:vanished",
                    relation: .leftOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:visible", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:visible", "app:new", Self.hiddenControl,
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("An anchored placement whose anchor sits in a later section is clamped to the end of its own section")
    func anchoredPlacementIsClampedToSectionEndWhenAnchorIsLater() {
        // The anchor lives in the hidden section but the placement names
        // .visible, and the section map commits to .visible either way.
        // The item stops at the visible section's end rather than
        // following the anchor across the boundary.
        let result = apply(
            placements: [
                "app:new": .newItemAnchored(
                    section: .visible,
                    anchorUID: "app:hidden",
                    relation: .rightOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [
                Self.chevron, "app:visible", Self.hiddenControl, "app:hidden", Self.alwaysHiddenControl,
            ]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:visible", "app:new", Self.hiddenControl, "app:hidden",
            Self.alwaysHiddenControl,
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("An anchored placement whose anchor sits in an earlier section is clamped to the start of its own section")
    func anchoredPlacementIsClampedToSectionStartWhenAnchorIsEarlier() {
        // Mirror of the previous test in the other direction: the anchor
        // is left of the hidden control, but the placement names .hidden.
        let result = apply(
            placements: [
                "app:new": .newItemAnchored(
                    section: .hidden,
                    anchorUID: "app:visible",
                    relation: .leftOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [
                Self.chevron, "app:visible", Self.hiddenControl, "app:hidden", Self.alwaysHiddenControl,
            ]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:visible", Self.hiddenControl, "app:new", "app:hidden",
            Self.alwaysHiddenControl,
        ])
        #expect(result.sectionMap["app:new"] == "hidden")
    }

    // MARK: - Pass 1: saved placements

    @Test("A saved placement anchors to the left of the closest successor still present")
    func savedPlacementAnchorsLeftOfSuccessor() {
        let result = apply(
            placements: ["app:a": .saved(section: .visible, index: 0)],
            unmanagedUIDs: ["app:a"],
            desiredFiltered: [Self.chevron, "app:c", Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:a", "app:b", "app:c"]]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:a", "app:c", Self.hiddenControl,
        ])
        #expect(result.sectionMap["app:a"] == "visible")
    }

    @Test("A saved placement anchors to the right of the closest predecessor when no successor remains")
    func savedPlacementAnchorsRightOfPredecessor() {
        let result = apply(
            placements: ["app:c": .saved(section: .visible, index: 2)],
            unmanagedUIDs: ["app:c"],
            desiredFiltered: [Self.chevron, "app:a", Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:a", "app:b", "app:c"]]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:a", "app:c", Self.hiddenControl,
        ])
    }

    @Test("A saved placement with no surviving anchors lands at the section start, right of the chevron")
    func savedPlacementWithoutAnchorsLandsRightOfChevron() {
        let result = apply(
            placements: ["app:new": .saved(section: .visible, index: 0)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:unrelated", Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:new"]]
        )

        // Never left of the chevron.
        #expect(result.desiredFiltered == [
            Self.chevron, "app:new", "app:unrelated", Self.hiddenControl,
        ])
    }

    @Test("A visible saved placement lands at index 0 when there is no chevron uid")
    func savedPlacementLandsLeftmostWithoutChevron() {
        let result = apply(
            placements: ["app:new": .saved(section: .visible, index: 0)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: ["app:unrelated", Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:new"]],
            controlUIDs: ControlUIDs(visible: nil, hidden: Self.hiddenControl, alwaysHidden: nil)
        )

        #expect(result.desiredFiltered == [
            "app:new", "app:unrelated", Self.hiddenControl,
        ])
    }

    @Test("A saved placement whose section has no recorded saved order lands at the section start")
    func savedPlacementWithMissingSavedSequenceLandsAtSectionStart() {
        let result = apply(
            placements: ["app:new": .saved(section: .hidden, index: 3)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, Self.hiddenControl, "app:hidden"],
            savedSectionOrder: [:],
            controlUIDs: ControlUIDs(visible: Self.chevron, hidden: Self.hiddenControl, alwaysHidden: nil)
        )

        #expect(result.desiredFiltered == [
            Self.chevron, Self.hiddenControl, "app:new", "app:hidden",
        ])
        #expect(result.sectionMap["app:new"] == "hidden")
    }

    @Test("A saved hidden placement is appended when the hidden control is missing from the sequence")
    func savedHiddenPlacementAppendsWhenHiddenControlAbsent() {
        // The hidden control uid is declared but never appears, so the
        // section start collapses to the end of the sequence.
        let result = apply(
            placements: ["app:new": .saved(section: .hidden, index: 0)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:visible"],
            savedSectionOrder: ["hidden": ["app:new"]],
            controlUIDs: ControlUIDs(visible: Self.chevron, hidden: Self.hiddenControl, alwaysHidden: nil)
        )

        #expect(result.desiredFiltered == [Self.chevron, "app:visible", "app:new"])
        #expect(result.sectionMap["app:new"] == "hidden")
    }

    @Test("A saved always-hidden placement is appended when the always-hidden section is disabled")
    func savedAlwaysHiddenPlacementAppendsWithoutAlwaysHiddenControl() {
        let result = apply(
            placements: ["app:new": .saved(section: .alwaysHidden, index: 0)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, Self.hiddenControl, "app:hidden"],
            savedSectionOrder: ["alwaysHidden": ["app:new"]],
            controlUIDs: ControlUIDs(visible: Self.chevron, hidden: Self.hiddenControl, alwaysHidden: nil)
        )

        #expect(result.desiredFiltered == [
            Self.chevron, Self.hiddenControl, "app:hidden", "app:new",
        ])
        #expect(result.sectionMap["app:new"] == "alwaysHidden")
    }

    @Test("Saved placements are restored in saved order regardless of the unmanagedUIDs order")
    func savedPlacementsSortByIndexNotInputOrder() {
        // unmanagedUIDs deliberately reversed relative to saved order.
        let result = apply(
            placements: [
                "app:a": .saved(section: .visible, index: 0),
                "app:b": .saved(section: .visible, index: 1),
            ],
            unmanagedUIDs: ["app:b", "app:a"],
            desiredFiltered: [Self.chevron, "app:c", Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:a", "app:b", "app:c"]]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:a", "app:b", "app:c", Self.hiddenControl,
        ])
    }

    @Test("Saved placements for different sections each land inside their own section")
    func savedPlacementsAreGroupedPerSection() {
        let result = apply(
            placements: [
                "app:ah": .saved(section: .alwaysHidden, index: 0),
                "app:v": .saved(section: .visible, index: 0),
                "app:h": .saved(section: .hidden, index: 0),
            ],
            unmanagedUIDs: ["app:ah", "app:v", "app:h"],
            desiredFiltered: [Self.chevron, Self.hiddenControl, Self.alwaysHiddenControl],
            savedSectionOrder: [
                "visible": ["app:v"],
                "hidden": ["app:h"],
                "alwaysHidden": ["app:ah"],
            ]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:v", Self.hiddenControl, "app:h", Self.alwaysHiddenControl, "app:ah",
        ])
        #expect(result.sectionMap["app:v"] == "visible")
        #expect(result.sectionMap["app:h"] == "hidden")
        #expect(result.sectionMap["app:ah"] == "alwaysHidden")
    }

    // MARK: - Pass interaction

    @Test("Saved placements are applied before default placements even when listed later")
    func savedPassRunsBeforeDefaultPass() {
        let result = apply(
            placements: [
                "app:default": .newItemDefault(section: .visible),
                "app:saved": .saved(section: .visible, index: 0),
            ],
            unmanagedUIDs: ["app:default", "app:saved"],
            desiredFiltered: [Self.chevron, Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:saved"]]
        )

        // The saved item precedes the default item despite coming second
        // in unmanagedUIDs.
        #expect(result.desiredFiltered == [
            Self.chevron, "app:saved", "app:default", Self.hiddenControl,
        ])
    }

    // MARK: - Caller invariant

    // The caller invariant is that unmanagedUIDs and desiredFiltered are
    // disjoint, which LayoutSolver.partitionUnmanagedUIDs guarantees.
    // Nothing enforces it at the type level, so these tests pin the
    // fail-safe: the placement is dropped and the desired layout's own
    // decision for that uid stands, rather than the uid appearing twice.

    @Test("A default placement for a uid already in the sequence is skipped rather than duplicating it")
    func defaultPlacementForAlreadyPresentUIDIsSkipped() {
        let result = apply(
            placements: ["app:dup": .newItemDefault(section: .visible)],
            unmanagedUIDs: ["app:dup"],
            desiredFiltered: [Self.chevron, "app:dup", Self.hiddenControl],
            sectionMap: ["app:dup": "visible"]
        )

        #expect(result.desiredFiltered == [Self.chevron, "app:dup", Self.hiddenControl])
        #expect(result.desiredFiltered.filter { $0 == "app:dup" }.count == 1)
    }

    @Test("An anchored placement for a uid already in the sequence is skipped and leaves the section map alone")
    func anchoredPlacementForAlreadyPresentUIDIsSkipped() {
        let result = apply(
            placements: [
                "app:dup": .newItemAnchored(
                    section: .hidden,
                    anchorUID: "app:hidden",
                    relation: .rightOfAnchor
                ),
            ],
            unmanagedUIDs: ["app:dup"],
            desiredFiltered: [Self.chevron, "app:dup", Self.hiddenControl, "app:hidden"],
            sectionMap: ["app:dup": "visible"]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:dup", Self.hiddenControl, "app:hidden",
        ])
        // Skipping means not relabelling either: a uid the function did
        // not move must not be tagged with a section it does not sit in.
        #expect(result.sectionMap["app:dup"] == "visible")
    }

    @Test("A saved placement for a uid already in the sequence is skipped rather than duplicating it")
    func savedPlacementForAlreadyPresentUIDIsSkipped() {
        let result = apply(
            placements: ["app:dup": .saved(section: .visible, index: 0)],
            unmanagedUIDs: ["app:dup"],
            desiredFiltered: [Self.chevron, "app:other", "app:dup", Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:dup", "app:other"]]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:other", "app:dup", Self.hiddenControl,
        ])
    }

    /// The rightOf offset counts insertions, but the computed slot is then
    /// clamped into the named section. When the anchor lives left of that
    /// section, every slot clamps to the same section start, and counting
    /// does not help: the second item is inserted at the start again, ahead
    /// of the first, reversing exactly the group order #919 set out to
    /// preserve.
    @Test("rightOf items keep their order even when the anchor is outside their section")
    func rightOfAnchorOutsideSectionKeepsOrder() throws {
        let anchor = "vis1"
        let result = apply(
            placements: [
                "newA": .newItemAnchored(section: .alwaysHidden, anchorUID: anchor, relation: .rightOfAnchor),
                "newB": .newItemAnchored(section: .alwaysHidden, anchorUID: anchor, relation: .rightOfAnchor),
            ],
            unmanagedUIDs: ["newA", "newB"],
            desiredFiltered: [Self.chevron, anchor, Self.hiddenControl, Self.alwaysHiddenControl]
        )

        let a = result.desiredFiltered.firstIndex(of: "newA")
        let b = result.desiredFiltered.firstIndex(of: "newB")
        #expect(a != nil && b != nil)
        #expect(try #require(a) < b!, "newA was listed first in unmanagedUIDs, so it must stay left of newB")
    }

    /// A leftOf insertion at the clamped section start shifts every item
    /// already placed there one slot right. A landing site recorded as an
    /// *index* goes stale at that moment: the next rightOf item's floor is
    /// one slot low and it lands ahead of its predecessor, reversing the
    /// group. The floor must follow the placed item, not its old index.
    @Test("rightOf items keep their order when a leftOf insertion shifts the clamped section start")
    func rightOfAnchorKeepsOrderAcrossInterleavedLeftOfInsertion() throws {
        let anchor = "vis1"
        let result = apply(
            placements: [
                "newA": .newItemAnchored(section: .alwaysHidden, anchorUID: anchor, relation: .rightOfAnchor),
                "newB": .newItemAnchored(section: .alwaysHidden, anchorUID: anchor, relation: .leftOfAnchor),
                "newC": .newItemAnchored(section: .alwaysHidden, anchorUID: anchor, relation: .rightOfAnchor),
            ],
            unmanagedUIDs: ["newA", "newB", "newC"],
            desiredFiltered: [Self.chevron, anchor, Self.hiddenControl, Self.alwaysHiddenControl]
        )

        let a = result.desiredFiltered.firstIndex(of: "newA")
        let c = result.desiredFiltered.firstIndex(of: "newC")
        #expect(a != nil && c != nil)
        #expect(try #require(a) < c!, "newA was listed first in unmanagedUIDs, so it must stay left of newC")
    }
}
