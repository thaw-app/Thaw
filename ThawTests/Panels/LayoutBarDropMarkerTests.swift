//
//  LayoutBarDropMarkerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
struct LayoutBarDropMarkerTests {
    /// Three 24-point icons, 6 points apart.
    private let frames = [0, 30, 60].map { CGRect(x: CGFloat($0), y: 0, width: 24, height: 24) }

    /// The three icons as slots; nil marks one that is not an item, such as an opaque slot or a collapsed group.
    private func slots(_ itemIndices: [Int?], holdingItems: [Bool]? = nil) -> [LayoutBarDropMarker.Slot] {
        zip(frames, itemIndices).enumerated().map { offset, pair in
            LayoutBarDropMarker.Slot(
                frame: pair.0,
                itemIndex: pair.1,
                holdsItems: holdingItems?[offset] ?? (pair.1 != nil)
            )
        }
    }

    @Test("A dragged item's marker sits in the middle of the gap it holds open")
    func gapMarker() {
        #expect(LayoutBarDropMarker.x(inGap: [frames[1]]) == 42)
        #expect(LayoutBarDropMarker.x(inGap: [frames[0], frames[1]]) == 27)
        #expect(LayoutBarDropMarker.x(inGap: []) == nil)
    }

    @Test("A group lands before the nearest icon, or after it past its middle", arguments: [
        (x: CGFloat(-10), index: 0),
        (x: CGFloat(10), index: 0),
        (x: CGFloat(14), index: 1),
        (x: CGFloat(40), index: 1),
        (x: CGFloat(44), index: 2),
        (x: CGFloat(200), index: 3),
    ])
    func groupDestination(x: CGFloat, index: Int) {
        let destination = LayoutBarDropMarker.groupDestination(forX: x, among: slots([0, 1, 2]), itemCount: 3)
        #expect(destination == .init(itemIndex: index, boundary: index))
    }

    @Test("A slot that is not an item is skipped in the item list but not on the bar")
    func groupDestinationCountsItemsOnly() {
        let destination = LayoutBarDropMarker.groupDestination(forX: 70, among: slots([nil, 0, 1]), itemCount: 2)
        #expect(destination == .init(itemIndex: 1, boundary: 2))
    }

    @Test("A group dropped nearest a slot that is not an item goes to the end of the items, and is marked there")
    func groupDestinationFallsBackToTheEnd() {
        // Nearest the opaque slot in the middle: the marker is after the last item, not beside the slot.
        let middle = LayoutBarDropMarker.groupDestination(forX: 40, among: slots([0, nil, 1]), itemCount: 2)
        #expect(middle == .init(itemIndex: 2, boundary: 3))

        // A trailing opaque slot holds no items, so the end of the items is the boundary before it.
        let trailing = LayoutBarDropMarker.groupDestination(forX: 10, among: slots([nil, 0, nil]), itemCount: 1)
        #expect(trailing == .init(itemIndex: 1, boundary: 2))

        // A collapsed group is not an item, but its members are in the list, so the end is after it.
        let collapsed = LayoutBarDropMarker.groupDestination(
            forX: 70,
            among: slots([0, 1, nil], holdingItems: [true, true, true]),
            itemCount: 4
        )
        #expect(collapsed == .init(itemIndex: 4, boundary: 3))

        let empty = LayoutBarDropMarker.groupDestination(forX: 0, among: [], itemCount: 0)
        #expect(empty == .init(itemIndex: 0, boundary: 0))
    }

    @Test("A group's marker sits on the boundary it is inserted at", arguments: [
        (index: 0, x: CGFloat(0)),
        (index: 1, x: CGFloat(27)),
        (index: 2, x: CGFloat(57)),
        (index: 3, x: CGFloat(84)),
        (index: 9, x: CGFloat(84)),
    ])
    func boundaryMarker(index: Int, x: CGFloat) {
        #expect(LayoutBarDropMarker.x(insertingAt: index, among: frames) == x)
    }

    @Test("The marker stays whole at either end of the bar")
    func markerStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 84, height: 28)
        #expect(LayoutBarDropMarker.rect(atX: 0, in: bounds).minX == 0)
        #expect(LayoutBarDropMarker.rect(atX: 84, in: bounds).maxX == 84)
        #expect(LayoutBarDropMarker.rect(atX: 42, in: bounds) == CGRect(x: 41, y: 2, width: 2, height: 24))
    }
}
