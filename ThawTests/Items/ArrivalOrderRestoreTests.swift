//
//  ArrivalOrderRestoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@Suite("Recorded order across an arrival")
struct ArrivalOrderRestoreTests {
    private func preserved(
        saved: [String],
        mirrored: [String],
        previous: Set<String>,
        current: Set<String>
    ) -> [String]? {
        MenuBarItemManager.visibleOrderPreservedAcrossArrival(
            savedOrder: saved,
            mirroredOrder: mirrored,
            previousLive: previous,
            currentLive: current
        )
    }

    @Test("An arrival that shuffles the items already there keeps their recorded sequence")
    func arrivalShuffleKeepsRecordedSequence() {
        let result = preserved(
            saved: ["a", "b", "c"],
            mirrored: ["new", "c", "a", "b"],
            previous: ["a", "b", "c"],
            current: ["a", "b", "c", "new"]
        )
        #expect(result == ["new", "a", "b", "c"])
    }

    @Test("The newcomer stays in the slot macOS gave it")
    func newcomerKeepsItsSlot() {
        let result = preserved(
            saved: ["a", "b", "c"],
            mirrored: ["b", "new", "a", "c"],
            previous: ["a", "b", "c"],
            current: ["a", "b", "c", "new"]
        )
        #expect(result == ["a", "new", "b", "c"])
    }

    @Test("An arrival that leaves the others in order changes nothing")
    func orderlyArrivalIsLeftAlone() {
        let result = preserved(
            saved: ["a", "b", "c"],
            mirrored: ["a", "new", "b", "c"],
            previous: ["a", "b", "c"],
            current: ["a", "b", "c", "new"]
        )
        #expect(result == nil)
    }

    @Test("A reorder with the same items is the user's drag and is mirrored")
    func dragWithoutArrivalIsMirrored() {
        let result = preserved(
            saved: ["a", "b", "c"],
            mirrored: ["c", "a", "b"],
            previous: ["a", "b", "c"],
            current: ["a", "b", "c"]
        )
        #expect(result == nil)
    }

    @Test("A departure, or a swap of one item for another, is not an arrival")
    func departureAndSwapAreNotArrivals() {
        #expect(preserved(
            saved: ["a", "b", "c"],
            mirrored: ["c", "a"],
            previous: ["a", "b", "c"],
            current: ["a", "c"]
        ) == nil)
        #expect(preserved(
            saved: ["a", "b", "c"],
            mirrored: ["c", "a", "new"],
            previous: ["a", "b", "c"],
            current: ["a", "c", "new"]
        ) == nil)
    }

    @Test("Saved entries for closed apps keep their slots")
    func closedAppEntriesAreUntouched() {
        let result = preserved(
            saved: ["a", "closed", "b"],
            mirrored: ["new", "b", "closed", "a"],
            previous: ["a", "b"],
            current: ["a", "b", "new"]
        )
        #expect(result == ["new", "a", "closed", "b"])
    }

    @Test("The arrival restore enforces order without drags or user privileges")
    func arrivalRestoreReasonIsWriteOnly() {
        let reason = LayoutChangeReason.arrivalRestore
        #expect(reason.permitsOrderEnforcement)
        #expect(reason.isPositionWriteOnly)
        #expect(!reason.isUserInitiated)
        #expect(!reason.isAuthoredEdit)
        #expect(!LayoutChangeReason.userReorder.isPositionWriteOnly)
    }
}
