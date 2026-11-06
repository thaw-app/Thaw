//
//  LayoutMoveSequencePlannerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// Moves use same-section anchors from the LCS or already-moved items.
/// Searches forward before backward, then falls back to the section boundary.
@Suite("Plan LCS move sequence")
struct LayoutMoveSequencePlannerTests {
    private typealias Planner = LayoutMoveSequencePlanner

    // MARK: - Scenarios

    /// Only overlapping items can move; an empty current layout has no observed items to place.
    @Test("An empty current layout produces no moves")
    func emptyCurrentProducesNoMovesDueToFilter() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: [],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.isEmpty,
                "items missing from currentNoControls are filtered out before LCS work, so no moves are produced")
    }

    @Test("An already-matching layout produces no moves")
    func identicalCurrentAndDesiredNoMoves() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result == [])
    }

    /// A single swap needs one move anchored to an LCS-stable item.
    @Test("A single swap plans exactly one move against an LCS-stable anchor")
    func singleSwapPlansOneMove() {
        // The backtrack tie-break picks {b,c} over {a,c}, leaving a to move.
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["b", "a", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "a")
        // The forward scan finds c, an LCS-stable anchor in the same section.
        #expect(result.first?.destination == .leftOfUID("c"))
    }

    /// Unobserved h1 is filtered out; the LCS keeps x, the same-section anchor left of v1.
    @Test("The anchor scan stays inside the moving item's section")
    func anchorScanRespectsSectionBoundary() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["v1", "x"],
            desiredNoControls: ["x", "v1", "h1"],
            sectionMap: ["v1": "visible", "x": "visible", "h1": "hidden"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "v1")
        #expect(result.first?.destination == .rightOfUID("x"))
    }

    /// The nearest forward stable anchor c wins over the backward anchor a.
    @Test("The forward anchor scan is preferred over the backward one")
    func forwardScanPreferredOverBackward() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["b", "a", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "b")
        #expect(result.first?.destination == .leftOfUID("c"))
    }

    /// The LCS keeps x in visible, leaving h1 without a hidden-section anchor.
    @Test("With no same-section anchor the planner falls back to the section boundary")
    func sectionBoundaryFallbackWhenNoAnchorInSection() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["h1", "x"],
            desiredNoControls: ["x", "h1"],
            sectionMap: ["h1": "hidden", "x": "visible"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "h1")
        if case let .sectionBoundary(section) = result.first?.destination {
            #expect(section == .hidden)
        } else {
            Issue.record("expected .sectionBoundary(.hidden), got \(String(describing: result.first?.destination))")
        }
    }

    /// The LCS keeps c; b moves after c and then becomes a stable anchor for a.
    @Test("An already-moved item becomes a stable anchor for later moves")
    func alreadyMovedItemBecomesStableAnchor() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["c", "b", "a"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.count == 2)
        #expect(result[0].uid == "b")
        #expect(result[0].destination == .rightOfUID("c"))
        #expect(result[1].uid == "a")
        #expect(result[1].destination == .rightOfUID("b"))
    }

    // MARK: - Preferred movers

    /// The new item and b tie in the LCS; prefer moving the arrival over the established item.
    @Test("An unmanaged arrival moves instead of an established item")
    func unmanagedArrivalIsPreferredMover() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "new"],
            desiredNoControls: ["a", "new", "b"],
            sectionMap: ["a": "hidden", "b": "hidden", "new": "hidden"],
            preferredMoveUIDs: ["new"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "new")
        #expect(result.first?.destination == .leftOfUID("b"))
    }

    /// The weighting is only a tie-break. If the unmanaged item already sits
    /// correctly, it remains in the LCS and no move is invented.
    @Test("A correctly placed unmanaged item remains stable")
    func correctlyPlacedUnmanagedItemDoesNotMove() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "new", "b"],
            desiredNoControls: ["a", "new", "b"],
            sectionMap: ["a": "hidden", "b": "hidden", "new": "hidden"],
            preferredMoveUIDs: ["new"]
        )

        #expect(result.isEmpty)
    }

    /// Preferred movers only resolve ties between equally long subsequences.
    /// They must not trade one established move for two unmanaged moves.
    @Test("Preferred movers never shorten the LCS")
    func preferredMoversDoNotShortenLCS() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c", "n1", "n2"],
            desiredNoControls: ["a", "b", "n1", "n2", "c"],
            sectionMap: [
                "a": "hidden", "b": "hidden", "c": "hidden",
                "n1": "hidden", "n2": "hidden",
            ],
            preferredMoveUIDs: ["n1", "n2"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "c")
    }

    /// Without preferred movers, the default LCS tie-break moves b.
    @Test("Without preferred movers the historical tie-break is unchanged")
    func noPreferredMoversKeepsHistoricalTieBreak() {
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "new"],
            desiredNoControls: ["a", "new", "b"],
            sectionMap: ["a": "hidden", "b": "hidden", "new": "hidden"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "b")
    }

    // MARK: - Unanchorable anchors

    /// The chevron's position is persisted, but anchoring failed moves to a divider repeatedly shoves it left.
    /// Use a neighbouring app item instead; right-to-left layout amplifies wrong-side insertions rejected by ordinal checks.
    @Test("A control item is not chosen as an anchor when an app item is available")
    func controlItemIsNotChosenAsAnchor() {
        let sectionMap = ["a": "visible", "chevron": "visible", "b": "visible", "c": "visible"]
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["a", "chevron", "b", "c"],
            desiredNoControls: ["a", "chevron", "c", "b"],
            sectionMap: sectionMap,
            unanchorableUIDs: ["chevron"]
        )

        for move in result {
            if case let .leftOfUID(uid) = move.destination {
                #expect(uid != "chevron", "planned a move anchored on the chevron")
            }
            if case let .rightOfUID(uid) = move.destination {
                #expect(uid != "chevron", "planned a move anchored on the chevron")
            }
        }
    }

    /// With no eligible stable item, fall back to the section boundary rather than dropping the move.
    @Test("With no app-item anchor available the move falls back to the boundary")
    func fallsBackToBoundaryWhenOnlyControlItemRemains() {
        // Only the chevron is stable, and it is unanchorable.
        let result = Planner.planLCSMoveSequence(
            currentNoControls: ["chevron", "b"],
            desiredNoControls: ["b", "chevron"],
            sectionMap: ["chevron": "visible", "b": "visible"],
            unanchorableUIDs: ["chevron"]
        )

        #expect(!result.isEmpty, "the move must still be planned")
        for move in result {
            if case .sectionBoundary = move.destination {
                continue
            }
            if case let .leftOfUID(uid) = move.destination {
                #expect(uid != "chevron")
            }
            if case let .rightOfUID(uid) = move.destination {
                #expect(uid != "chevron")
            }
        }
    }

    /// Omitting unanchorableUIDs is equivalent to passing an empty set.
    @Test("With no unanchorable set the planner behaves exactly as before")
    func emptyUnanchorableSetIsUnchanged() {
        let current = ["a", "b", "c"]
        let desired = ["b", "a", "c"]
        let map = ["a": "visible", "b": "visible", "c": "visible"]

        #expect(
            Planner.planLCSMoveSequence(
                currentNoControls: current,
                desiredNoControls: desired,
                sectionMap: map
            ) == Planner.planLCSMoveSequence(
                currentNoControls: current,
                desiredNoControls: desired,
                sectionMap: map,
                unanchorableUIDs: []
            )
        )
    }
}

// MARK: - Layout storm replay

/// Replays field data from LayoutStormLog to guard against whole-row layout churn.
/// Prefix-trimmed full sorting replays the entire tail when one early item is displaced.
@Suite("Layout storm replay (#881)")
struct LayoutStormReplayTests {
    private typealias Planner = LayoutMoveSequencePlanner

    /// Only LM Studio is displaced: it sits left of Sound and Google Drive instead of right.
    @Test("Only the newly arrived item is out of place")
    func onlyTheNewItemIsOutOfPlace() {
        let current = LayoutStormLog.currentVisible
        let desired = LayoutStormLog.desiredVisible

        #expect(Set(current) == Set(desired), "same items, different order")

        let newItem = "ai.elementlabs.lmstudio:Item-0"
        #expect(current.filter { $0 != newItem } == desired.filter { $0 != newItem })
    }

    /// One displaced item should cost one move.
    @Test("The planner moves one item, not the whole row")
    func plannerMovesOnlyTheDisplacedItem() {
        let moves = Planner.planLCSMoveSequence(
            currentNoControls: LayoutStormLog.currentVisible + LayoutStormLog.currentHidden,
            desiredNoControls: LayoutStormLog.desiredVisible + LayoutStormLog.currentHidden,
            sectionMap: LayoutStormLog.sectionMap
        )

        #expect(moves.count == 1)
        #expect(moves.first?.uid == "ai.elementlabs.lmstudio:Item-0")
    }

    /// The field log records ten drags over 4.1 seconds for this single displacement.
    @Test("The deleted full-sort path dragged ten items for the same input")
    func fullSortDraggedTheEntireRow() {
        let moves = Planner.planLCSMoveSequence(
            currentNoControls: LayoutStormLog.currentVisible + LayoutStormLog.currentHidden,
            desiredNoControls: LayoutStormLog.desiredVisible + LayoutStormLog.currentHidden,
            sectionMap: LayoutStormLog.sectionMap
        )

        #expect(LayoutStormLog.fullSortDraggedItems.count == 10)
        #expect(moves.count < LayoutStormLog.fullSortDraggedItems.count)
    }

    /// n - |LCS| is the minimum move count for unique IDs.
    /// Do not trade extra synthetic drags for faster microsecond-scale planning.
    @Test("The move count matches the theoretical floor")
    func moveCountIsOptimal() {
        let current = LayoutStormLog.currentVisible
        let desired = LayoutStormLog.desiredVisible
        let retained = Planner.longestCommonSubsequence(current, desired)

        #expect(desired.count - retained.count == 1)
    }

    /// No-op cache cycles must not churn the bar on every tick.
    @Test("An already-correct row plans no moves")
    func steadyStatePlansNothing() {
        let moves = Planner.planLCSMoveSequence(
            currentNoControls: LayoutStormLog.desiredVisible,
            desiredNoControls: LayoutStormLog.desiredVisible,
            sectionMap: LayoutStormLog.sectionMap
        )
        #expect(moves.isEmpty)
    }
}

/// Field-log fixture from a notched 14-inch display: 1728×1117, notch 771…956, right boundary 1538.
/// LM Studio arrived two slots early (x=1066, Sound x≈1106, Drive x=1142), causing ten prefix-trimmed drags over 4.1 seconds.
private enum LayoutStormLog {
    /// Visible section in logged left-to-right order.
    static let currentVisible = [
        "com.apple.controlcenter:FocusModes",
        "ai.elementlabs.lmstudio:Item-0",
        "com.apple.controlcenter:Sound",
        "com.google.drivefs:Item-0",
        "com.adobe.acc.AdobeCreativeCloud:Item-0",
        "com.displaylink.DisplayLinkUserAgent:Item-0",
        "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        "com.if.Amphetamine:Amphetamine",
        "com.ameba.TRex:Item-1",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:UserSwitcher",
        "com.apple.controlcenter:WiFi",
        "com.apple.controlcenter:Battery",
    ]

    /// Hidden section in logged left-to-right order.
    static let currentHidden = [
        "org.tabby:Item-0",
        "com.electron.dockerdesktop:Item-0",
        "com.apple.systemuiserver:com.apple.menuextra.TimeMachine",
    ]

    /// The three leading items are reconstructed from visibleUIDs.count=13 and the logged ten-item tail.
    /// The seven trimmed entries are three hidden items, the hidden control, and three visible items.
    static let desiredVisible = [
        "com.apple.controlcenter:FocusModes",
        "com.apple.controlcenter:Sound",
        "com.google.drivefs:Item-0",
        "ai.elementlabs.lmstudio:Item-0",
        "com.adobe.acc.AdobeCreativeCloud:Item-0",
        "com.displaylink.DisplayLinkUserAgent:Item-0",
        "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        "com.if.Amphetamine:Amphetamine",
        "com.ameba.TRex:Item-1",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:UserSwitcher",
        "com.apple.controlcenter:WiFi",
        "com.apple.controlcenter:Battery",
    ]

    /// Drag order transcribed from the field log's full-sort moves.
    static let fullSortDraggedItems = [
        "ai.elementlabs.lmstudio:Item-0",
        "com.adobe.acc.AdobeCreativeCloud:Item-0",
        "com.displaylink.DisplayLinkUserAgent:Item-0",
        "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        "com.if.Amphetamine:Amphetamine",
        "com.ameba.TRex:Item-1",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:UserSwitcher",
        "com.apple.controlcenter:WiFi",
        "com.apple.controlcenter:Battery",
    ]

    static let sectionMap: [String: String] = {
        var map = [String: String]()
        for uid in currentVisible {
            map[uid] = "visible"
        }
        for uid in currentHidden {
            map[uid] = "hidden"
        }
        return map
    }()
}
