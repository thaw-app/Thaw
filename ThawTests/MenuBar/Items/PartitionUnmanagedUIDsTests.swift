//
//  PartitionUnmanagedUIDsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// `LayoutSolver.partitionUnmanagedUIDs`, the filter applyProfileLayout uses to
/// pick the UIDs that reach planUnmanagedPlacement.
///
/// 1. All three Thaw control items are excluded. saveSectionOrder never saves
///    them, so they would leak into NewItemsPlacement and make the LCS planner
///    emit spurious control-item moves every cycle ("Thaw icon keeps moving").
/// 2. Input order is preserved; the LCS planner iterates it for placement.
@Suite("Partition unmanaged UIDs")
struct PartitionUnmanagedUIDsTests {
    /// The original bug missed the visible control item.
    @Test("All three control items are excluded")
    func allThreeControlItemsExcluded() {
        let hidden = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"
        let ah = "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden"
        let visible = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
        let app = "com.example.app:Item-0"
        let currentFlat = [hidden, visible, app, ah]

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: [],
            hiddenCtrlUID: hidden,
            ahCtrlUID: ah,
            visibleCtrlUID: visible,
            provisionalIdentityUIDs: []
        )

        #expect(result == [app])
    }

    /// A nil control UID (such as a disabled always-hidden section) is tolerated.
    @Test("Nil control UIDs are tolerated and other exclusions still hold")
    func nilControlUIDsToleratedAndOtherExclusionsHold() {
        let hidden = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"
        let visible = "com.stonerl.Thaw:Thaw.ControlItem.Visible"
        let saved = "com.example.saved:Item-0"
        let unsaved = "com.example.fresh:Item-0"
        let currentFlat = [hidden, saved, visible, unsaved]

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: [saved],
            hiddenCtrlUID: hidden,
            ahCtrlUID: nil,
            visibleCtrlUID: visible,
            provisionalIdentityUIDs: []
        )

        #expect(result == [unsaved])
    }

    /// Only items the desired sequence doesn't know should reach planUnmanagedPlacement.
    @Test("Items already in desiredUIDs are excluded")
    func itemsInDesiredUIDsAreExcluded() {
        let saved = "com.example.saved:Item-0"
        let unsaved = "com.example.fresh:Item-0"

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [saved, unsaved],
            desiredUIDs: [saved],
            hiddenCtrlUID: nil,
            ahCtrlUID: nil,
            visibleCtrlUID: nil,
            provisionalIdentityUIDs: []
        )

        #expect(result == [unsaved])
    }

    /// The Little Snitch orphan case: a Control Center-hosted widget with no
    /// resolved source PID must not be relocated as an unmanaged arrival.
    @Test("Provisional-identity UIDs are excluded")
    func provisionalIdentityUIDsAreExcluded() {
        let orphan = "com.apple.controlcenter:Item-0"
        let app = "com.example.app:Item-0"

        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [orphan, app],
            desiredUIDs: [],
            hiddenCtrlUID: nil,
            ahCtrlUID: nil,
            visibleCtrlUID: nil,
            provisionalIdentityUIDs: [orphan]
        )

        #expect(result == [app])
    }

    /// The LCS planner iterates the result to decide insertion positions.
    @Test("Input order is preserved")
    func inputOrderIsPreserved() {
        let a = "com.example.a:Item-0"
        let b = "com.example.b:Item-0"
        let c = "com.example.c:Item-0"

        // Deliberately not alphabetical.
        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [c, a, b],
            desiredUIDs: [],
            hiddenCtrlUID: nil,
            ahCtrlUID: nil,
            visibleCtrlUID: nil,
            provisionalIdentityUIDs: []
        )

        #expect(result == [c, a, b])
    }

    /// No crash on any nil/non-nil control UID combination.
    @Test("An empty current layout returns an empty result")
    func emptyCurrentFlatReturnsEmpty() {
        let result = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: [],
            desiredUIDs: ["com.example.app:Item-0"],
            hiddenCtrlUID: "h",
            ahCtrlUID: "ah",
            visibleCtrlUID: "v",
            provisionalIdentityUIDs: []
        )

        #expect(result.isEmpty)
    }
}
