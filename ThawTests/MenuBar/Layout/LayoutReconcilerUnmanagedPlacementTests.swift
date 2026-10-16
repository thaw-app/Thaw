//
//  LayoutReconcilerUnmanagedPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``LayoutReconciler/applyUnmanagedPlacementsToDesired(placements:unmanagedUIDs:desiredFiltered:sectionMap:savedSectionOrder:controlUIDs:)``,
/// which splices unmanaged items into the desired sequence during a profile apply.
///
/// It mutates a positional array while deriving section bounds from it, so each
/// insertion shifts the bounds the next one uses; mistakes silently scramble the bar.
///
/// Index 0 is leftmost: chevron, visible items, hidden control, hidden items,
/// always-hidden control, always-hidden items.
@Suite("Layout reconciler unmanaged placement")
struct LayoutReconcilerUnmanagedPlacementTests {
    // MARK: - Fixtures

    private static let chevron = "control:visible"
    private static let hiddenControl = "control:hidden"
    private static let alwaysHiddenControl = "control:alwaysHidden"

    private static let allControls = ControlUIDs(
        visible: chevron,
        hidden: hiddenControl,
        alwaysHidden: alwaysHiddenControl
    )

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

    @Test("A visible default placement ignores a chevron parked mid-section")
    func visibleDefaultIgnoresParkedChevron() {
        // The chevron can sit anywhere in visible, so a default item still goes at the section start.
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .visible)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: ["app:left", Self.chevron, "app:right", Self.hiddenControl]
        )

        #expect(result.desiredFiltered == [
            "app:new", "app:left", Self.chevron, "app:right", Self.hiddenControl,
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("A visible default placement lands after a leading chevron")
    func visibleDefaultLandsAfterLeadingChevron() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .visible)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [Self.chevron, "app:visible", Self.hiddenControl, "app:hidden"]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, "app:new", "app:visible", Self.hiddenControl, "app:hidden",
        ])
        #expect(result.sectionMap["app:new"] == "visible")
    }

    @Test("A hidden default placement lands at the start of the hidden section when always-hidden is on")
    func hiddenDefaultLandsAfterHiddenControlWithAlwaysHidden() {
        let result = apply(
            placements: ["app:new": .newItemDefault(section: .hidden)],
            unmanagedUIDs: ["app:new"],
            desiredFiltered: [
                Self.chevron, Self.hiddenControl, "app:hidden",
                Self.alwaysHiddenControl, "app:alwaysHidden",
            ]
        )

        #expect(result.desiredFiltered == [
            Self.chevron, Self.hiddenControl, "app:new", "app:hidden",
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
        // The hidden control uid is declared but absent, so no boundary exists.
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

    @Test("A leftOfAnchor placement keeps its slot when the chevron trails the visible section (#1069)")
    func anchoredLeftOfAnchorWithTrailingChevron() {
        // The reporter's bar: the Thaw icon trails visible, the New items badge sits left of its leftmost item.
        let result = apply(
            placements: [
                "neat.software.Tim:Item-0": .newItemAnchored(
                    section: .visible,
                    anchorUID: "com.intelliscapesolutions.caffeine:Item-0",
                    relation: .leftOfAnchor
                ),
            ],
            unmanagedUIDs: ["neat.software.Tim:Item-0"],
            desiredFiltered: [
                "com.intelliscapesolutions.caffeine:Item-0",
                "com.apparentsoft.trickster:Item-0",
                "com.bjango.istatmenus.status:com.bjango.istatmenus.time",
                Self.chevron,
                Self.hiddenControl,
            ]
        )

        #expect(result.desiredFiltered == [
            "neat.software.Tim:Item-0",
            "com.intelliscapesolutions.caffeine:Item-0",
            "com.apparentsoft.trickster:Item-0",
            "com.bjango.istatmenus.status:com.bjango.istatmenus.time",
            Self.chevron,
            Self.hiddenControl,
        ])
        #expect(result.sectionMap["neat.software.Tim:Item-0"] == "visible")
    }

    @Test("The #1069 placement plans a move left of the anchor, not right of the item beside the chevron")
    func trailingChevronPlacementPlansMoveLeftOfAnchor() {
        let tim = "neat.software.Tim:Item-0"
        let caffeine = "com.intelliscapesolutions.caffeine:Item-0"
        let trickster = "com.apparentsoft.trickster:Item-0"
        let istatTime = "com.bjango.istatmenus.status:com.bjango.istatmenus.time"
        let applied = apply(
            placements: [
                tim: .newItemAnchored(section: .visible, anchorUID: caffeine, relation: .leftOfAnchor),
            ],
            unmanagedUIDs: [tim],
            desiredFiltered: [caffeine, trickster, istatTime, Self.chevron, Self.hiddenControl],
            sectionMap: [caffeine: "visible", trickster: "visible", istatTime: "visible", Self.chevron: "visible"]
        )

        // Where macOS put Tim before the apply, as logged.
        let moves = LayoutSolver.planLCSMoveSequence(
            currentNoControls: [caffeine, trickster, tim, istatTime, Self.chevron],
            desiredNoControls: applied.desiredFiltered.filter { $0 != Self.hiddenControl },
            sectionMap: applied.sectionMap,
            unanchorableUIDs: [Self.chevron],
            preferredMoveUIDs: [tim]
        )

        #expect(moves == [LayoutSolver.LCSPlannedMove(uid: tim, destination: .leftOfUID(caffeine))])
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

    // `planUnmanagedPlacement` gives every unanchored item the same `.newItemAnchored`
    // placement, so shared anchors are common. The group keeps its unmanagedUIDs order.

    @Test("Several rightOfAnchor placements sharing one anchor keep their unmanagedUIDs order")
    func rightOfAnchorPlacementsPreserveUnmanagedOrder() {
        // Inserting after the anchor does not shift it, so a naive pass reuses
        // `anchorIdx + 1` and reverses the group; it must advance past placed items.
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
        // leftOf already keeps order because each insert shifts the anchor right;
        // pinned so the rightOf fix cannot regress it.
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
        // `.sectionDefault` ignores the anchor riding along, so the item goes after
        // "app:tail" as if the anchor had vanished.
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
        // The anchor is in hidden but the placement names visible, so the item stops
        // at visible's end instead of following the anchor.
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
        // Mirror: the anchor is left of the hidden control, but the placement names hidden.
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
        // The hidden control uid is absent, so the section start collapses to the sequence end.
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

    @Test("A default placement at the New items slot precedes a saved placement at that slot")
    func defaultAtNewItemsSlotPrecedesSavedPlacement() {
        let result = apply(
            placements: [
                "app:default": .newItemDefault(section: .visible),
                "app:saved": .saved(section: .visible, index: 0),
            ],
            unmanagedUIDs: ["app:default", "app:saved"],
            desiredFiltered: [Self.chevron, Self.hiddenControl],
            savedSectionOrder: ["visible": ["app:saved"]]
        )

        // The "New items" badge sits at visible's start, so a new item lands there
        // ahead of a saved item targeting the same slot, even though saved runs first.
        #expect(result.desiredFiltered == [
            Self.chevron, "app:default", "app:saved", Self.hiddenControl,
        ])
    }

    // MARK: - Caller invariant

    // Callers keep unmanagedUIDs and desiredFiltered disjoint, but nothing enforces
    // it, so an overlapping placement is dropped instead of duplicating the uid.

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
        // A uid the function did not move must not be tagged with a section it is not in.
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

    /// The rightOf offset counts insertions, but when the anchor is left of the named
    /// section every slot clamps to the section start, reversing the group (#919).
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

    /// A leftOf insert at the clamped start shifts placed items right, so a landing
    /// site stored as an index goes stale; the floor must follow the placed item.
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
